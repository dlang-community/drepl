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
    EngineResult evalDecl(in char[] decl)
    {
        return EngineResult(true, decl.stripRight.idup);
    }

    EngineResult evalExpr(in char[] expr)
    {
        return EngineResult(true, expr.stripRight.idup);
    }

    EngineResult evalStmt(in char[] stmt)
    {
        return EngineResult(true, stmt.stripRight.idup);
    }
}

static assert(isEngine!EchoEngine);

unittest
{
    alias ER = EngineResult;

    auto e = echoEngine();
    assert(e.evalDecl("void foo() {\n}") == ER(true, "void foo() {\n}"));
    assert(e.evalExpr("3 * foo") == ER(true, "3 * foo"));
    assert(e.evalStmt("writeln(`foobar`);") == ER(true, "writeln(`foobar`);"));
}
