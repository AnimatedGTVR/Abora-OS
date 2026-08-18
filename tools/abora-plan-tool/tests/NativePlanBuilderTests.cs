using System.Text.Json;
using AboraPlanTool;
using Xunit;

namespace AboraPlanTool.Tests;

public class NativePlanBuilderTests
{
    [Fact]
    public void BuildsAPlanFromEveryCommandType()
    {
        var content = "set hostname nativehost\nenable bluetooth\ndisable openssh\npackage add git\npackage remove vim\n";
        var result = NativePlanBuilder.Build(content, "1");

        Assert.Null(result.Error);
        var doc = JsonDocument.Parse(result.PlanJson!);
        Assert.Equal(1, doc.RootElement.GetProperty("planVersion").GetInt32());
        Assert.Equal("anix", doc.RootElement.GetProperty("language").GetString());
        var ops = doc.RootElement.GetProperty("operations");
        Assert.Equal(5, ops.GetArrayLength());
        Assert.Equal("set", ops[0].GetProperty("op").GetString());
        Assert.Equal("hostname", ops[0].GetProperty("key").GetString());
        Assert.Equal("nativehost", ops[0].GetProperty("value").GetString());
        Assert.Equal("enable", ops[1].GetProperty("op").GetString());
        Assert.Equal("bluetooth", ops[1].GetProperty("feature").GetString());
        Assert.Equal("disable", ops[2].GetProperty("op").GetString());
        Assert.Equal("package.add", ops[3].GetProperty("op").GetString());
        Assert.Equal("git", ops[3].GetProperty("name").GetString());
        Assert.Equal("package.remove", ops[4].GetProperty("op").GetString());
    }

    [Fact]
    public void SkipsBlankLinesAndComments()
    {
        var content = "\n  # a comment\nenable bluetooth\n   \n";
        var result = NativePlanBuilder.Build(content, "1");

        Assert.Null(result.Error);
        var doc = JsonDocument.Parse(result.PlanJson!);
        Assert.Equal(1, doc.RootElement.GetProperty("operations").GetArrayLength());
    }

    [Fact]
    public void ReportsLineNumberOnUsageError()
    {
        var content = "enable bluetooth\nset onlyonearg\n";
        var result = NativePlanBuilder.Build(content, "1");

        Assert.Null(result.PlanJson);
        Assert.StartsWith("2:", result.Error);
        Assert.Contains("usage: set <key> <value>", result.Error);
    }

    [Fact]
    public void RejectsUnknownCommand()
    {
        var result = NativePlanBuilder.Build("launch-missiles now\n", "1");
        Assert.Contains("unknown ANIX Native command: launch-missiles", result.Error);
    }

    [Fact]
    public void RejectsInvalidPackageAction()
    {
        var result = NativePlanBuilder.Build("package frobnicate git\n", "1");
        Assert.Contains("package action must be add or remove", result.Error);
    }

    [Fact]
    public void StopsAtFirstError()
    {
        var content = "enable bluetooth\nbadcommand\nenable audio\n";
        var result = NativePlanBuilder.Build(content, "1");
        Assert.StartsWith("2:", result.Error);
    }

    // Splitting the file's content on '\n' alone leaves a trailing '\r' on
    // every line of a CRLF-line-ended .anix file (a plausible real file --
    // hand-edited on Windows, or via WSL/an editor that defaults to CRLF).
    // enable/disable/package tokenize with a plain whitespace split, which
    // treats '\r' as a delimiter and drops it. "set" used to be different:
    // its 3-way-capped split's last piece is the untouched line remainder,
    // so the '\r' rode along inside the captured value
    // (`abora.hostname = "myhost\r";` once written to Nix) instead of
    // being stripped.
    [Fact]
    public void StripsTrailingCarriageReturnFromCrlfLines()
    {
        var content = "set hostname myhost\r\nset gc.dates Sun 03:00:00\r\nenable bluetooth\r\n";
        var result = NativePlanBuilder.Build(content, "1");

        Assert.Null(result.Error);
        var doc = JsonDocument.Parse(result.PlanJson!);
        var ops = doc.RootElement.GetProperty("operations");
        Assert.Equal("myhost", ops[0].GetProperty("value").GetString());
        Assert.Equal("Sun 03:00:00", ops[1].GetProperty("value").GetString());
        Assert.Equal("bluetooth", ops[2].GetProperty("feature").GetString());
    }
}
