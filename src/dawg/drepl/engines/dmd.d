/*
  Copyright: Martin Nowak 2013 -
  License: Subject to the terms of the MIT license, as written in the included LICENSE file.
  Authors: $(WEB code.dawg.eu, Martin Nowak)
*/
module dawg.drepl.engines.dmd;
import dawg.drepl.engines;
import std.algorithm, std.exception, std.file, std.path, std.process, std.range, std.stdio, std.string, std.typecons;

DMDEngine dmdEngine()
{
    import core.sys.posix.unistd, std.random;
    auto compiler = environment.get("DMD", "dmd");
    auto tmpDir = format("/tmp/.drepl-%d/%d", getuid(), uniform(0, 1000));
    return DMDEngine(compiler, tmpDir);
}

struct DMDEngine
{
    ProcessPipes _compiler;
    string _tmpDir;
    size_t _id;

    @disable this(this);

    this(string compiler, string tmpDir)
    {
        _tmpDir = tmpDir;
        if (_tmpDir.exists) rmdirRecurse(_tmpDir);
        mkdirRecurse(_tmpDir);
    }

    ~this()
    {
        if (_tmpDir) rmdirRecurse(_tmpDir);
    }

    Tuple!(EngineResult, string) evalDecl(in char[] decl)
    {
        auto path = buildPath(_tmpDir, format("__mod%s", _id));
        auto f = writeHeader(path);
        f.writefln(q{
            %1$s

            extern(C) string[] __decls()
            {
                return [__traits(allMembers, __mod%2$s)];
            }
            }.outdent(), decl, _id);
        f.close();

        if (auto err = compileModule(path))
            return error(err);

        ++_id;

        import core.runtime, core.demangle, core.sys.posix.dlfcn;

        auto lib = Runtime.loadLibrary(path~".so");
        if (lib is null)
        {
            auto msg = dlerror(); import core.stdc.string : strlen;
            return error("failed to load "~path~".so ("~msg[0 .. strlen(msg)].idup~")");
        }
        auto func = cast(string[] function())dlsym(lib, "__decls");
        try
            return success(func()[1 .. $].filter!(d => !d.startsWith("_")).join(", "));
        catch (Exception e)
            return error(e.toString());
    }

    Tuple!(EngineResult, string) evalExpr(in char[] expr)
    {
        auto path = buildPath(_tmpDir, format("__mod%s", _id));
        auto f = writeHeader(path);
        f.writefln(q{
                extern(C) string __expr()
                {
                    static if (is(typeof(%1$s) == string))
                    {
                        return (%1$s).idup; // copy static strings to GC heap
                    }
                    else static if (is(typeof(%1$s) == void))
                    {
                        return "void".idup;
                    }
                    else
                    {
                        import std.conv : to;
                        return to!string(%1$s);
                    }
                }
            }.outdent(), expr);
        f.close();

        if (auto err = compileModule(path))
            return error(err);

        ++_id;

        import core.runtime, core.demangle, core.sys.posix.dlfcn;

        auto lib = Runtime.loadLibrary(path~".so");
        if (lib is null)
        {
            auto msg = dlerror(); import core.stdc.string : strlen;
            return error("failed to load "~path~".so ("~msg[0 .. strlen(msg)].idup~")");
        }
        auto func = cast(string function())dlsym(lib, "__expr");
        try
            return success(func());
        catch (Exception e)
            return error(e.toString());
    }

    Tuple!(EngineResult, string) evalStmt(in char[] stmt)
    {
        auto path = buildPath(_tmpDir, format("__mod%s", _id));
        auto f = writeHeader(path);
        f.writefln(q{
                extern(C) void __run()
                {
                    %s
                }
            }, stmt);
        f.close();

        if (auto err = compileModule(path))
            return error(err);

        ++_id;

        import core.runtime, core.demangle, core.sys.posix.dlfcn;

        auto lib = Runtime.loadLibrary(path~".so");
        if (lib is null)
        {
            auto msg = dlerror(); import core.stdc.string : strlen;
            return error("failed to load "~path~".so ("~msg[0 .. strlen(msg)].idup~")");
        }
        auto func = cast(void function())dlsym(lib, "__run");
        try
            return func(), success("");
        catch (Exception e)
            return error(e.toString());
    }

private:
    File writeHeader(string path)
    {
        auto f = File(path~".d", "w");
        if (_id > 0)
        {
            f.write("import __mod0");
            foreach (i; 0 .. _id)
                f.writef(", __mod%s", i);
            f.write(";");
        }
        return f;
    }

    string compileModule(string path)
    {
        auto args = ["dmd", "-I"~_tmpDir, "-of"~path~".so", "-fPIC",
                     "-shared", path, "-L-l:libphobos2.so"];
        foreach (i; 0 .. _id)
            args ~= "-L"~_tmpDir~format("/__mod%s.so", i);
        auto dmd = execute(args);
        if (dmd.status != 0)
        {
            auto err = dmd.output;
            err = err.find("Error: ");
            return err[7 .. $].stripRight();
        }
        if (!exists(path~".so"))
            return path~".so not found";
        return null;
    }

    Tuple!(EngineResult, string) error(string msg)
    {
        return tuple(EngineResult.error, msg);
    }

    Tuple!(EngineResult, string) success(string msg)
    {
        return tuple(EngineResult.success, msg);
    }
}

static assert(isEngine!DMDEngine);
