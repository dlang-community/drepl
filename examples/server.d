import vibe.d, std.algorithm, std.range;

shared static this()
{
    auto settings = new HTTPServerSettings;
    settings.port = 8080;
    settings.bindAddresses = ["::1", "127.0.0.1"];
    if (getOption("bindAddress|bind", &settings.bindAddresses[0], "Sets the address used for serving."))
        settings.bindAddresses.length = 1;
    getOption("port|p", &settings.port, "Sets the port used for serving.");

    auto router = new URLRouter;
    router
        .get("/", &drepl)
        .get("/ws/dmd", handleWebSockets(&runSession))
        ;

    logInfo("serving");
    listenHTTP(settings, router);
}

void drepl(HTTPServerRequest req, HTTPServerResponse res)
{
    res.render!"drepl.dt"();
}

void runSession(WebSocket sock)
{
    import std.process;
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
