using AboraPlanTool;
using Xunit;

namespace AboraPlanTool.Tests;

public class PlanParserTests
{
    private const string V = "1";

    [Fact]
    public void AcceptsAWellFormedPlan()
    {
        var json = """
        {"planVersion":1,"language":"test","operations":[
          {"op":"set","key":"hostname","value":"planhost"},
          {"op":"enable","feature":"bluetooth"},
          {"op":"package.add","name":"firefox"}
        ]}
        """;

        var result = PlanParser.Parse(json, V);

        Assert.True(result.Success);
        Assert.Equal("test", result.Plan!.Language);
        Assert.Equal(3, result.Plan.Operations.Count);
        Assert.Equal(new PlanOperation("set", "hostname", "planhost"), result.Plan.Operations[0]);
        Assert.Equal(new PlanOperation("enable", "bluetooth", ""), result.Plan.Operations[1]);
        Assert.Equal(new PlanOperation("package.add", "firefox", ""), result.Plan.Operations[2]);
    }

    [Fact]
    public void RejectsMalformedJson()
    {
        var result = PlanParser.Parse("{not json", V);
        Assert.False(result.Success);
        Assert.Contains(result.Errors, e => e.Contains("not valid JSON"));
    }

    [Fact]
    public void RejectsWrongPlanVersion()
    {
        var json = """{"planVersion":2,"operations":[]}""";
        var result = PlanParser.Parse(json, V);
        Assert.False(result.Success);
        Assert.Contains(result.Errors, e => e.Contains("Unsupported plan version"));
    }

    [Fact]
    public void RejectsMissingPlanVersion()
    {
        var json = """{"operations":[]}""";
        var result = PlanParser.Parse(json, V);
        Assert.False(result.Success);
        Assert.Contains(result.Errors, e => e.Contains("missing"));
    }

    [Fact]
    public void RejectsMissingOperationsArray()
    {
        var json = """{"planVersion":1}""";
        var result = PlanParser.Parse(json, V);
        Assert.False(result.Success);
        Assert.Contains(result.Errors, e => e.Contains("operations"));
    }

    [Fact]
    public void RejectsUnknownSetKey()
    {
        var json = """{"planVersion":1,"operations":[{"op":"set","key":"not-a-real-key","value":"x"}]}""";
        var result = PlanParser.Parse(json, V);
        Assert.False(result.Success);
        Assert.Contains(result.Errors, e => e.Contains("unknown set key"));
    }

    [Fact]
    public void RejectsSetWithoutValue()
    {
        var json = """{"planVersion":1,"operations":[{"op":"set","key":"hostname"}]}""";
        var result = PlanParser.Parse(json, V);
        Assert.False(result.Success);
        Assert.Contains(result.Errors, e => e.Contains("requires a value"));
    }

    [Fact]
    public void RejectsInvalidPackageName()
    {
        var json = """{"planVersion":1,"operations":[{"op":"package.add","name":"firefox; rm -rf /"}]}""";
        var result = PlanParser.Parse(json, V);
        Assert.False(result.Success);
        Assert.Contains(result.Errors, e => e.Contains("invalid package name"));
    }

    [Fact]
    public void RejectsUnknownOp()
    {
        var json = """{"planVersion":1,"operations":[{"op":"launch-missiles"}]}""";
        var result = PlanParser.Parse(json, V);
        Assert.False(result.Success);
        Assert.Contains(result.Errors, e => e.Contains("unknown op"));
    }

    [Fact]
    public void PassesThroughUnknownFeatureNameWithoutValidatingIt()
    {
        // feature_to_anix_key validation is bash's job, not this tool's --
        // see PlanParser's class doc comment for why.
        var json = """{"planVersion":1,"operations":[{"op":"enable","feature":"totally-made-up"}]}""";
        var result = PlanParser.Parse(json, V);
        Assert.True(result.Success);
        Assert.Equal("totally-made-up", result.Plan!.Operations[0].Field1);
    }

    [Fact]
    public void ReportsMultipleFailuresInOneRun()
    {
        var json = """
        {"planVersion":1,"operations":[
          {"op":"set","key":"bogus","value":"x"},
          {"op":"package.add","name":"bad name!"}
        ]}
        """;
        var result = PlanParser.Parse(json, V);
        Assert.False(result.Success);
        Assert.Equal(2, result.Errors.Count);
    }

    [Fact]
    public void DefaultsLanguageToEmptyWhenAbsent()
    {
        var json = """{"planVersion":1,"operations":[]}""";
        var result = PlanParser.Parse(json, V);
        Assert.True(result.Success);
        Assert.Equal("", result.Plan!.Language);
        Assert.Empty(result.Plan.Operations);
    }
}
