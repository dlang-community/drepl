/*
  Copyright: Martin Nowak 2013 -
  License: Subject to the terms of the MIT license, as written in the included LICENSE file.
  Authors: $(WEB code.dawg.eu, Martin Nowak)
*/
module dawg.drepl.interpreter;
import dawg.drepl.engines, dawg.drepl.parser;
import std.algorithm, std.array, std.conv, std.string, std.typecons, std.typetuple;

enum Result
{
    success,
    error,
    incomplete,
}


struct Interpreter(Engine) if (isEngine!Engine)
{
    Tuple!(Result, string) interpret(in char[] line)
    {
        import std.string : chomp, stripRight;

        // ignore empty lines on empty input
        if (!_incomplete.data.length && !line.length)
            return tuple(Result.success, "");

        // if line is empty, but _incomplete is not, force parse
        bool forceParse = (_incomplete.data.length && !line.length);

        _incomplete.put(line);
        _incomplete.put('\n');
        auto input = _incomplete.data;

        // dismiss buffer after two consecutive empty lines
        if (input.endsWith("\n\n\n"))
        {
            _incomplete.clear();
            return tuple(Result.error, "You typed two blank lines. Starting a new command.");
        }

        auto parseResult = parse(input);

        if (parseResult[0] && !forceParse)
            return tuple(Result.incomplete, "");

        _incomplete.clear();

        if (parseResult[0] && forceParse)
            return tuple(Result.error, "Error parsing '"~input.strip.idup~"'.");

        Tuple!(EngineResult, string)[] res;

        foreach(atom; parseResult[1])
        {
            final switch(atom.kind) with(AtomKind)
            {
            case Stmt: res ~= _engine.evalStmt(atom.source); break;
            case Decl: res ~= _engine.evalDecl(atom.source); break;
            case Expr: res ~= _engine.evalExpr(atom.source.stripRight().chomp(";")); break;
            case Auto: res ~= _engine.evalDecl(atom.source); break; // TODO: implement re-write
            }
        }

        auto engResult = res.canFind!( (a,b) => a[0] == b )(EngineResult.error) ? EngineResult.error : EngineResult.success;
        auto strResult = res.map!( a => a[1] ).join("\n").stripRight();

        return tuple(toResult(engResult), strResult);
    }

private:

    import stdx.d.lexer, stdx.d.parser;

    Tuple!(bool, Atom[]) parse(in char[] input)
    {
        scope parser = new ReplParser();
        static bool hasErr;
        hasErr = false;
        parser.fileName = "drepl";
        parser.messageFunction = (file, ln, col, msg, isErr) { if (isErr) hasErr = true; };
        auto atoms = parser.parse(input);
        return tuple(hasErr, atoms);
    }

    static toResult(EngineResult er)
    {
        final switch (er)
        {
        case EngineResult.success: return Result.success;
        case EngineResult.error: return Result.error;
        }
    }

    Engine _engine;
    Appender!(const(char)[]) _incomplete;
}

Interpreter!Engine interpreter(Engine)(auto ref Engine e) if (isEngine!Engine)
{
    return Interpreter!Engine(move(e));
}

unittest
{
    auto intp = interpreter(echoEngine());
    assert(intp.interpret("3 * foo") == tuple(Result.success, "3 * foo"));
    assert(intp.interpret("stmt!(T)();") == tuple(Result.success, "stmt!(T)();"));
    assert(intp.interpret("auto a = 3 * foo;") == tuple(Result.success, "auto a = 3 * foo;"));

    void testMultiline(string input)
    {
        import std.string : splitLines;
        auto lines = splitLines(input);
        foreach (line; lines[0 .. $-1])
            assert(intp.interpret(line) == tuple(Result.incomplete, ""));
        assert(intp.interpret(lines[$-1]) == tuple(Result.success, input));
    }

    testMultiline(
        q{void foo() {
            }});

    testMultiline(
        q{int foo() {
                auto bar(int v) { return v; }
                auto v = 3 * 12;
                return bar(v);
            }});

    testMultiline(
        q{struct Foo(T) {
                void bar() {
                }
            }});

    testMultiline(
        q{struct Foo(T) {
                void bar() {

                }
            }});

    auto intp = interpreter(echoEngine());
    assert(intp.interpret("struct Foo {")[0] == Result.incomplete);
    assert(intp.interpret("")[0] == Result.incomplete);
    assert(intp.interpret("")[0] == Result.error);
}
