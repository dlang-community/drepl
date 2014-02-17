/*
  Copyright: Martin Nowak 2013 -
  License: Subject to the terms of the MIT license, as written in the included LICENSE file.
  Authors: $(WEB code.dawg.eu, Martin Nowak)
*/
module dawg.drepl.engines.echo;
import dawg.drepl.engines;
import std.typecons, std.string : stripRight;

EchoEngine echoEngine()
{
    return EchoEngine();
}

struct EchoEngine
{
    Tuple!(EngineResult, string) evalDecl(in char[] decl)
    {
        return tuple(EngineResult.success, decl.stripRight.idup);
    }

    Tuple!(EngineResult, string) evalExpr(in char[] expr)
    {
        return tuple(EngineResult.success, expr.stripRight.idup);
    }

    Tuple!(EngineResult, string) evalStmt(in char[] stmt)
    {
        return tuple(EngineResult.success, stmt.stripRight.idup);
    }
}

static assert(isEngine!EchoEngine);

unittest
{
    static auto success(string msg) { return tuple(EngineResult.success, msg); }
    auto e = echoEngine();
    assert(e.evalDecl("void foo() {\n}") == success("void foo() {\n}"));
    assert(e.evalExpr("3 * foo") == success("3 * foo"));
    assert(e.evalStmt("writeln(`foobar`);") == success("writeln(`foobar`);"));
}
