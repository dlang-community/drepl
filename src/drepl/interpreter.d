/*
  Copyright: Martin Nowak 2013 -
  License: Subject to the terms of the MIT license, as written in the included LICENSE file.
  Authors: $(WEB code.dawg.eu, Martin Nowak)
*/
module drepl.interpreter;
import drepl.engines;
import std.algorithm, std.array, std.conv, std.string, std.typecons;

struct InterpreterResult
{
    enum State
    {
        success,
        error,
        incomplete
    }

    State state;
    string stdout, stderr;
}

struct Interpreter(Engine) if (isEngine!Engine)
{
    alias IR = InterpreterResult;
    IR interpret(const(char)[] line)
    {
        // ignore empty lines or comment without incomplete input
        if (!_incomplete.data.length && (!line.length || byToken(cast(ubyte[])line).empty))
            return IR(IR.State.success);

        _incomplete.put(line);
        _incomplete.put('\n');
        auto input = _incomplete.data;

        // dismiss buffer after two consecutive empty lines
        if (input.endsWith("\n\n\n"))
        {
            _incomplete.clear();
            return IR(IR.State.error, "", "You typed two blank lines. Starting a new command.");
        }

        immutable kind = classify(input);
        EngineResult res;
        final switch (kind)
        {
        case Kind.Decl:
            res = _engine.evalDecl(input);
            break;
        case Kind.Stmt:
            res = _engine.evalStmt(input);
            break;
        case Kind.Expr:
            res = _engine.evalExpr(input);
            break;

        case Kind.WhiteSpace:
            return IR(IR.State.success);

        case Kind.Incomplete:
            return IR(IR.State.incomplete);

        case Kind.Error:
            _incomplete.clear();
            return IR(IR.State.error, "", "Error parsing '"~input.strip.idup~"'.");
        }
        _incomplete.clear();
        return IR(res.success ? IR.State.success : IR.State.error, res.stdout, res.stderr);
    }

private:
    enum Kind { Decl, Stmt, Expr, WhiteSpace, Incomplete, Error, }

    import dparse.lexer : getTokensForParser, LexerConfig, byToken, Token, StringCache, tok;
    import dparse.parser : Parser;

    Kind classify(in char[] input)
    {
        scope cache = new StringCache(StringCache.defaultBucketCount);
        auto tokens = getTokensForParser(cast(ubyte[])input, LexerConfig(), cache);
        if (tokens.empty) return Kind.WhiteSpace;

        auto tokenIds = tokens.map!(t => t.type)();
        if (!tokenIds.balancedParens(tok!"{", tok!"}") ||
            !tokenIds.balancedParens(tok!"(", tok!")") ||
            !tokenIds.balancedParens(tok!"[", tok!"]"))
            return Kind.Incomplete;

        import std.typetuple : TypeTuple;
        foreach (kind; TypeTuple!(Kind.Decl, Kind.Stmt, Kind.Expr))
            if (parse!kind(tokens))
                return kind;
        return Kind.Error;
    }

    bool parse(Kind kind)(in Token[] tokens)
    {
        import dparse.rollback_allocator : RollbackAllocator;
        scope parser = new Parser();
        RollbackAllocator allocator;
        static bool hasErr;
        hasErr = false;
        parser.fileName = "drepl";
        parser.setTokens(tokens);
        parser.allocator = &allocator;
        parser.messageDg = delegate(string file, size_t ln, size_t col, string msg, bool isErr) { // @suppress(dscanner.suspicious.unused_parameter)
            if (isErr)
                hasErr = true;
        };
        static if (kind == Kind.Decl)
        {
            do
            {
                if (!parser.parseDeclaration()) return false;
            } while (parser.moreTokens());
        }
        else static if (kind == Kind.Stmt)
        {
            do
            {
                if (!parser.parseStatement()) return false;
            } while (parser.moreTokens());
        }
        else static if (kind == Kind.Expr)
        {
            if (!parser.parseExpression() || parser.moreTokens())
                return false;
        }
        return !hasErr;
    }

    unittest
    {
        auto intp = interpreter(echoEngine());
        assert(intp.classify("3+2") == Kind.Expr);
        // only single expressions
        assert(intp.classify("3+2 foo()") == Kind.Error);
        assert(intp.classify("3+2;") == Kind.Stmt);
        // multiple statements
        assert(intp.classify("3+2; foo();") == Kind.Stmt);
        assert(intp.classify("struct Foo {}") == Kind.Decl);
        // multiple declarations
        assert(intp.classify("void foo() {} void bar() {}") == Kind.Decl);
        // can't currently mix declarations and statements
        assert(intp.classify("void foo() {} foo();") == Kind.Error);
        // or declarations and expressions
        assert(intp.classify("void foo() {} foo()") == Kind.Error);
        // or statments and expressions
        assert(intp.classify("foo(); foo()") == Kind.Error);

        assert(intp.classify("import std.stdio;") == Kind.Decl);
    }

    Engine _engine;
    Appender!(char[]) _incomplete;
}

Interpreter!Engine interpreter(Engine)(return scope Engine e) if (isEngine!Engine)
{
    // workaround Issue 18540
    return Interpreter!Engine(() @trusted { return move(e); }());
}

unittest
{
    alias IR = InterpreterResult;
    auto intp = interpreter(echoEngine());
    assert(intp.interpret("3 * foo") == IR(IR.State.success, "3 * foo"));
    assert(intp.interpret("stmt!(T)();") == IR(IR.State.success, "stmt!(T)();"));
    assert(intp.interpret("auto a = 3 * foo;") == IR(IR.State.success, "auto a = 3 * foo;"));

    void testMultiline(string input)
    {
        import std.string : splitLines;
        auto lines = splitLines(input);
        foreach (line; lines[0 .. $-1])
            assert(intp.interpret(line) == IR(IR.State.incomplete, ""));
        assert(intp.interpret(lines[$-1]) == IR(IR.State.success, input));
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
}

unittest
{
    alias IR = InterpreterResult;
    auto intp = interpreter(echoEngine());
    assert(intp.interpret("struct Foo {").state == IR.State.incomplete);
    assert(intp.interpret("").state == IR.State.incomplete);
    assert(intp.interpret("").state == IR.State.error);

    assert(intp.interpret("struct Foo {").state == IR.State.incomplete);
    assert(intp.interpret("").state == IR.State.incomplete);
    assert(intp.interpret("}").state == IR.State.success);
}

unittest
{
    alias IR = InterpreterResult;
    auto intp = interpreter(echoEngine());
    assert(intp.interpret("//comment").state == IR.State.success);
    assert(intp.interpret("//comment").state == IR.State.success);

    assert(intp.interpret("struct Foo {").state == IR.State.incomplete);
    assert(intp.interpret("//comment").state == IR.State.incomplete);
    assert(intp.interpret("//comment").state == IR.State.incomplete);
    assert(intp.interpret("").state == IR.State.incomplete);
    assert(intp.interpret("//comment").state == IR.State.incomplete);
    assert(intp.interpret("").state == IR.State.incomplete);
    assert(intp.interpret("").state == IR.State.error);
}
