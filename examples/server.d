import vibe.d;
import dawg.drepl;

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
        .get("*", serveStaticFiles("./public/"))
        .get("/ws/echo", handleWebSockets(s => runSession(s, echoEngine())))
        .get("/ws/dmd", handleWebSockets(s => runSession(s, dmdEngine())))
        ;

    logInfo("serving");
    listenHTTP(settings, router);
}

void drepl(HTTPServerRequest req, HTTPServerResponse res)
{
    res.render!"drepl.dt"();
}

void runSession(E)(WebSocket sock, E engine)
{
    import std.conv : to;
    auto intp = interpreter(engine);
    auto resp = Json.emptyObject;
    while (sock.connected)
    {
        auto msg = sock.receiveText();
        auto res = intp.interpret(msg);

        resp.result = to!string(res[0]);
        resp.text = res[1].htmlEscape();
        sock.send((scope stream) => writeJsonString(stream, resp));
    }
}
