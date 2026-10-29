const std = @import("std");

/// roc-markdown's build: the package's own tests, and its judge, a Zig
/// program that holds every case of every corpus to its frozen answers
/// through the package (judge/answers.roc on judge/platform/, built to an
/// archive by the pinned Roc).
///
///   zig build test                     roc test, then the judge
///   zig build judge -- --also <gold>   the judge, with a private corpus
///   zig build repl                     markdown at a prompt, or piped
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    linuxOnly(target.result);

    const roc = rocCompiler(b);
    const answers = answersArchive(b, roc, rocOpt(optimize));

    // **THE JUDGE FINDS ITS DATA BY A BUILD OPTION**, never from the working
    // directory: judge/data, wherever the judge is run from.
    const paths = b.addOptions();
    paths.addOption([]const u8, "data", dataFolder(b));

    const judge_mod = b.createModule(.{
        .root_source_file = b.path("judge/judge.zig"),
        .target = target,
        .optimize = optimize,
    });
    judge_mod.addImport("judge_paths", paths.createModule());
    judge_mod.addObjectFile(answers);
    const judge_exe = b.addExecutable(.{ .name = "judge", .root_module = judge_mod });

    const judge = b.addRunArtifact(judge_exe);
    judge.addPassthruArgs();
    judge.has_side_effects = true;
    b.step("judge", "Every corpus through the package, held to its frozen answers (-- --also <corpus>, --raise, --time)").dependOn(&judge.step);

    // **THE PACKAGE AT A PROMPT** (judge/repl.zig): the judge's seam, the
    // same archive, at a terminal or a pipe.
    const repl_mod = b.createModule(.{
        .root_source_file = b.path("judge/repl.zig"),
        .target = target,
        .optimize = optimize,
    });
    repl_mod.addObjectFile(answers);
    const repl_exe = b.addExecutable(.{ .name = "repl", .root_module = repl_mod });
    const repl = b.addRunArtifact(repl_exe);
    repl.stdio = .inherit;
    b.step("repl", "Type markdown, see the package's answers (:help at the prompt)").dependOn(&repl.step);

    // **ONE COMMAND RUNS EVERY TEST**: the package's own expects, then the
    // judge over the committed corpora.
    const tests = b.step("test", "Every test: roc test package/main.roc, then the judge");
    const roc_test = b.addSystemCommand(&.{ roc, "test", "package/main.roc" });
    roc_test.setCwd(b.path("."));
    for (rocInputs(b)) |f| roc_test.addFileInput(b.path(f));
    roc_test.has_side_effects = true;
    tests.dependOn(&roc_test.step);
    const judged = b.addRunArtifact(judge_exe);
    judged.has_side_effects = true;
    judged.step.dependOn(&roc_test.step);
    tests.dependOn(&judged.step);

    // The REPL, piped, against the judge's frozen answers
    // (judge/repl_check.zig).
    const check_mod = b.createModule(.{
        .root_source_file = b.path("judge/repl_check.zig"),
        .target = target,
        .optimize = optimize,
    });
    check_mod.addImport("judge_paths", paths.createModule());
    const check_exe = b.addExecutable(.{ .name = "repl_check", .root_module = check_mod });
    const repl_checked = b.addRunArtifact(check_exe);
    repl_checked.addArtifactArg(repl_exe);
    repl_checked.has_side_effects = true;
    repl_checked.step.dependOn(&roc_test.step);
    tests.dependOn(&repl_checked.step);
}

/// judge/data, absolute (0.17 removed `b.pathFromRoot`).
fn dataFolder(b: *std.Build) []const u8 {
    const root = b.root.root_dir.handle.realPathFileAlloc(b.graph.io, b.root.subPathOrDot(), b.allocator) catch |e|
        std.process.fatal("the build root {f}: {t}", .{ b.root, e });
    return b.pathJoin(&.{ root, "judge", "data" });
}

/// **LINUX ON X86-64 ONLY, SAID AT CONFIGURE**: the archive is built for
/// x64musl.
fn linuxOnly(t: std.Target) void {
    if (t.os.tag != .linux or t.cpu.arch != .x86_64)
        std.process.fatal("roc-markdown's judge builds for x86-64 Linux only, not {t}-{t}", .{ t.cpu.arch, t.os.tag });
}

const roc_pin = std.mem.trim(u8, @embedFile("roc-version"), " \n");

/// **THE ROC IS PINNED** (roc-version): -Droc=<path>, or `roc` on the PATH,
/// and it must be the pinned one. (roc-chat's build.zig's.)
fn rocCompiler(b: *std.Build) []const u8 {
    const named = b.option([]const u8, "roc", "the Roc compiler (default: `roc` on the PATH); the version roc-version pins") orelse "roc";
    const none = "the package is Roc, and there is no Roc compiler at `{s}`: put Roc {s} (roc-version) on the PATH (showell/roc-apps release toolchain-2026-10-27 carries it), or name it with -Droc=<path>";
    const found = if (std.mem.indexOfScalar(u8, named, '/') == null)
        b.findProgram(.{ .names = &.{named} }) orelse std.process.fatal(none, .{ named, roc_pin })
    else
        b.root.root_dir.handle.realPathFileAlloc(b.graph.io, named, b.allocator) catch std.process.fatal(none, .{ named, roc_pin });
    const said = std.mem.trim(u8, b.run(&.{ found, "version" }), " \n");
    const version = if (std.mem.lastIndexOfScalar(u8, said, ' ')) |i| said[i + 1 ..] else said;
    if (!std.mem.eql(u8, version, roc_pin)) std.process.fatal("roc-markdown is pinned to Roc {s} (roc-version), and `{s}` is {s}: put the pinned one on the PATH or name it with -Droc=<path>", .{ roc_pin, found, version });
    return found;
}

/// **ROC'S BUILD MODE FOLLOWS ZIG'S**: a Debug build takes Roc's dev
/// backend, a release build LLVM. Roc's own default is `speed`, minutes
/// where dev takes about a second.
const RocOpt = enum { dev, speed };

fn rocOpt(optimize: std.lang.Optimize) RocOpt {
    return if (optimize == .debug) .dev else .speed;
}

/// judge/answers.roc built for x64musl, as `answers-x64musl.a`.
fn answersArchive(b: *std.Build, roc: []const u8, opt: RocOpt) std.Build.LazyPath {
    const run = b.addSystemCommand(&.{ roc, "build", "judge/answers.roc", "--target=x64musl", b.fmt("--opt={t}", .{opt}) });
    run.setCwd(b.path("."));
    for (rocInputs(b)) |f| run.addFileInput(b.path(f));
    // The compiler too: a new Roc builds the archive again.
    run.addFileInput(.{ .cwd_relative = roc });
    return run.addPrefixedOutputFileArg("--output=", "answers-x64musl.a");
}

/// **EVERY ROC MODULE IS AN INPUT, FOUND, NEVER LISTED**: each `.roc` in
/// the package, the judge's app and its platform.
fn rocInputs(b: *std.Build) []const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    for ([_][]const u8{ "package", "judge", "judge/platform" }) |folder| rocFiles(b, folder, &out);
    return out.items;
}

fn rocFiles(b: *std.Build, folder: []const u8, out: *std.ArrayList([]const u8)) void {
    const io = b.graph.io;
    var dir = b.root.root_dir.handle.openDir(io, folder, .{ .iterate = true }) catch |e|
        std.process.fatal("the package's Roc: cannot open {s} ({t})", .{ folder, e });
    defer dir.close(io);
    var it = dir.iterate();
    while (it.next(io) catch |e| std.process.fatal("the package's Roc: cannot list {s} ({t})", .{ folder, e })) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".roc")) continue;
        out.append(b.allocator, b.fmt("{s}/{s}", .{ folder, entry.name })) catch @panic("OOM");
    }
}
