import vibe.d, std.algorithm, std.range;

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
    while (sock.connected)
    {
        auto msg = sock.receiveText();
        p.stdin.writeln(msg); p.stdin.flush();

        // TODO: use non-blocking TCP sockets
        auto resp = Json(
            p.stdout.byLine()
            .find("===SOC===").drop(1).until("===EOC===")
            .map!htmlEscape.map!Json.array());

        sock.send((scope stream) => writeJsonString(stream, resp));
    }
}
