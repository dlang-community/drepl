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
}

void drepl(HTTPServerRequest req, HTTPServerResponse res)
{
    res.render!"drepl.dt"();
}

void runSession(WebSocket sock)
{
    import std.process;
    // TODO: should use app path, not ./ for the sandbox binary
    auto p = pipeShell("sandbox -M ./drepl_sandbox");
    fcntl(p.stdout.fileno, F_SETFL, O_NONBLOCK);
    Appender!(char[]) buf;
    while (sock.connected)
    {
        auto msg = sock.receiveText();
        p.stdin.writeln(msg); p.stdin.flush();

        // TODO: use non-blocking TCP sockets
        immutable t0 = Clock.currTime();
        while (true)
        {
            if (Clock.currTime() - t0 >= 5.seconds)
            {
                auto resp = Json(
                    ["error", "Command '"~msg~"' timed out, killing process."].map!Json.array());
                sock.send((scope stream) => writeJsonString(stream, resp));
                p.pid.kill(SIGKILL);
                return;
            }

            char[1024] smBuf = void;
            auto res = read(p.stdout.fileno, &smBuf[0], smBuf.length);
            if (res < 0)
            {
                errnoEnforce(errno == EAGAIN);
                // TODO: yield doesn't really seem to allow parallel sessions
                yield();
                continue;
            }

            buf.put(smBuf[0 .. res]);
            if (res < smBuf.length)
            {
                auto resp = Json(
                    buf.data.splitter('\n')
                    .find("===SOC===").drop(1).until("===EOC===")
                    .map!htmlEscape.map!Json.array());
                sock.send((scope stream) => writeJsonString(stream, resp));
                buf.clear();
                break;
            }
        }
    }
}
