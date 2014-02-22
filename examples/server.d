import vibe.d, std.algorithm, std.datetime, std.exception, std.range;
import core.stdc.errno, core.sys.posix.fcntl, core.sys.posix.unistd, core.sys.posix.signal : SIGKILL;

shared static this()
{
    auto settings = new HTTPServerSettings;
    if (getOption("bindAddress|bind", &settings.bindAddresses[0], "Sets the address used for serving."))
        settings.bindAddresses.length = 1;
    getOption("port|p", &settings.port, "Sets the port used for serving.");

    auto router = new URLRouter;
    router
        .get("/", &drepl)
        .get("/ws/dmd", handleWebSockets(&runSession))
        ;

    listenHTTP(settings, router);

    bool ssl;
    if (getOption("ssl", &ssl, "Enable SSL encryption."))
    {
        auto sslSettings = new HTTPServerSettings;
        sslSettings.bindAddresses = sslSettings.bindAddresses;
        sslSettings.sslContext = new SSLContext("ssl/crt.pem", "ssl/key.pem", SSLVersion.tls1);
        sslSettings.port = 443;
        getOption("ssl-port", &sslSettings.port, "Sets the port used for serving.");
        listenHTTP(sslSettings, router);
    }
}

void drepl(HTTPServerRequest req, HTTPServerResponse res)
{
    res.render!"drepl.dt"();
}

void sendError(WebSocket sock, string error)
{
    auto resp = Json.emptyObject;
    resp.state = "error";
    resp.stdout = Json.emptyArray;
    resp.stderr = [Json(error)];
    sock.send((scope stream) => writeJsonString(stream, resp));
}

void runSession(WebSocket sock)
{
    import std.process, core.runtime : Runtime;
    auto sandbox = Runtime.args[0].replace("drepl_server", "drepl_sandbox");
    auto p = pipeProcess(["sandbox", "-M", sandbox]);
    scope (exit) if (!tryWait(p.pid).terminated) p.pid.kill(SIGKILL);
    fcntl(p.stdout.fileno, F_SETFL, O_NONBLOCK);

    scope readEvt = createFileDescriptorEvent(p.stdout.fileno, FileDescriptorEvent.Trigger.read);

    Appender!(char[]) buf;

    while (sock.connected)
    {
        string msg;
        try
            msg = sock.receiveText(true);
        catch (Exception e)
            return sock.sendError("Received invalid WebSocket message.");

        p.stdin.writeln(msg);
        p.stdin.flush();

        if (!readEvt.wait(5.seconds, FileDescriptorEvent.Trigger.read))
            return sock.sendError("Command '"~msg~"' timed out.");

        auto rc = tryWait(p.pid);
        if (rc.terminated)
            return sock.sendError("Command '"~msg~"' terminated with "~to!string(rc.status)~".");

        char[1024] smBuf = void;
        ptrdiff_t res;
        while ((res = read(p.stdout.fileno, &smBuf[0], smBuf.length)) == smBuf.length)
            buf.put(smBuf[]);

        if (res < 0 && errno != EAGAIN)
            return sock.sendError("Internal error reading process output.");
        buf.put(smBuf[0 .. max(res, 0)]);

        try
        {
            auto resp = parseJsonString(buf.data.idup);
            resp.stdout = resp.stdout.get!string.splitter('\n').map!htmlEscapeMin.map!Json.array;
            resp.stderr = resp.stderr.get!string.splitter('\n').map!htmlEscapeMin.map!Json.array;
            sock.send((scope stream) => writeJsonString(stream, resp));
            buf.clear();
        }
        catch (Exception e)
        {
            return sock.sendError("Internal error reading process output.");
        }
    }
}
