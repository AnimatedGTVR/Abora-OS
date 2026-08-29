using AboraUpdateResolver;
using Xunit;

namespace AboraUpdateResolver.Tests;

public class VersionUtilTests
{
    [Theory]
    [InlineData("v4.1-DEMO2", "4.1")]
    [InlineData("v3.14", "3.14")]
    [InlineData("4.0", "4.0")]
    [InlineData("v4.0-EVEREST-ALPHA", "4.0")]
    [InlineData("edge", "edge")] // no leading digit: sed's no-match-unchanged behavior
    public void TagBaseVersion_MatchesBashSed(string tag, string expected) =>
        Assert.Equal(expected, VersionUtil.TagBaseVersion(tag));

    [Theory]
    [InlineData("v4.0", true)]
    [InlineData("v3.14", true)]
    [InlineData("v4.0-EVEREST-ALPHA", false)]
    [InlineData("edge", false)]
    [InlineData("4.0", false)] // missing leading "v"
    public void IsFinalReleaseTag_MatchesBashRegex(string tag, bool expected) =>
        Assert.Equal(expected, VersionUtil.IsFinalReleaseTag(tag));

    [Theory]
    [InlineData("v4.0-EVEREST-ALPHA", true)]
    [InlineData("v4.1-DEMO2", true)]
    [InlineData("v4.1-rc1", true)]
    [InlineData("v3.14", false)]
    [InlineData("edge", false)]
    public void IsDemoReleaseTag_MatchesBashRegex(string tag, bool expected) =>
        Assert.Equal(expected, VersionUtil.IsDemoReleaseTag(tag));

    [Theory]
    [InlineData("3.14", "4.0", true)]
    [InlineData("4.0", "3.14", false)]
    [InlineData("4.0", "4.0", false)]
    [InlineData("4.9", "4.10", true)] // sort -V, not lexical string sort
    [InlineData("test-prealpha", "4.0", false)] // non-numeric refs never sort as "older"
    [InlineData("4.0", "test-prealpha", true)]
    public void VersionLessThan_ComparesNumerically(string a, string b, bool expected) =>
        Assert.Equal(expected, VersionUtil.VersionLessThan(a, b));

    [Fact]
    public void LatestTag_PicksHighestFinalTag() =>
        Assert.Equal("v3.14", VersionUtil.LatestTag(new[] { "v2.5.0", "v3.14" }));

    [Fact]
    public void LatestTag_EmptyInputReturnsNull() =>
        Assert.Null(VersionUtil.LatestTag(Array.Empty<string>()));
}

public class UpdateResolverTests
{
    // Mirrors check-scripts.sh's "runtime: resolver keeps 3.14 on v3.14"
    [Fact]
    public void Stable_KeepsInstalledVersionWhenItsTagIsLatestFinal()
    {
        var result = UpdateResolver.Resolve(
            "stable", "3.14", new[] { "v2.5.0", "v3.14" },
            edgeExists: false, fallbackMode: false, fallbackRef: "", preAlphaRef: "edge");

        Assert.Equal("v3.14", result?.EffectiveRef);
    }

    // Mirrors "runtime: resolver avoids stable-channel downgrade"
    [Fact]
    public void Stable_FallsBackToEdgeRatherThanOfferingOlderTag()
    {
        var result = UpdateResolver.Resolve(
            "stable", "3.14", new[] { "v2.5.0" },
            edgeExists: false, fallbackMode: false, fallbackRef: "", preAlphaRef: "edge");

        Assert.Equal("edge", result?.EffectiveRef);
    }

    // Mirrors "runtime: resolver falls back to edge when stable tags are unavailable"
    [Fact]
    public void Stable_FallsBackToEdgeWhenNoTagsReadable()
    {
        var result = UpdateResolver.Resolve(
            "stable", "4.0", Array.Empty<string>(),
            edgeExists: true, fallbackMode: false, fallbackRef: "", preAlphaRef: "edge");

        Assert.Equal("edge", result?.EffectiveRef);
        Assert.Contains("could not read release tags", result?.EffectiveRefReason);
    }

    [Fact]
    public void Stable_ReturnsNullWhenNoTagsAndNoEdge()
    {
        var result = UpdateResolver.Resolve(
            "stable", "4.0", Array.Empty<string>(),
            edgeExists: false, fallbackMode: false, fallbackRef: "", preAlphaRef: "edge");

        Assert.Null(result);
    }

    // Mirrors "runtime: resolver recognizes Everest alpha tags as development releases"
    [Fact]
    public void Demo_SelectsMatchingDemoTagForCurrentVersionLine()
    {
        var result = UpdateResolver.Resolve(
            "demo", "4.0", new[] { "v4.0-EVEREST-ALPHA", "v3.14" },
            edgeExists: false, fallbackMode: false, fallbackRef: "", preAlphaRef: "edge");

        Assert.Equal("v4.0-EVEREST-ALPHA", result?.EffectiveRef);
    }

    [Fact]
    public void Stable_UsesMatchingDemoTagWhenNoFinalTagExistsForLine()
    {
        var result = UpdateResolver.Resolve(
            "stable", "4.0", new[] { "v4.0-EVEREST-ALPHA" },
            edgeExists: false, fallbackMode: false, fallbackRef: "", preAlphaRef: "edge");

        Assert.Equal("v4.0-EVEREST-ALPHA", result?.EffectiveRef);
    }

    [Fact]
    public void Unstable_AlwaysTracksEdge()
    {
        var result = UpdateResolver.Resolve(
            "unstable", "4.0", new[] { "v99.0" },
            edgeExists: false, fallbackMode: false, fallbackRef: "", preAlphaRef: "edge");

        Assert.Equal("edge", result?.EffectiveRef);
    }

    [Fact]
    public void PreAlpha_UsesConfiguredPreAlphaRef()
    {
        var result = UpdateResolver.Resolve(
            "pre-alpha", "4.0", Array.Empty<string>(),
            edgeExists: false, fallbackMode: false, fallbackRef: "", preAlphaRef: "some-branch");

        Assert.Equal("some-branch", result?.EffectiveRef);
    }

    // Mirrors "runtime: resolver allows explicit fallback downgrade"
    [Fact]
    public void FallbackMode_AlwaysUsesFallbackRefRegardlessOfChannel()
    {
        var result = UpdateResolver.Resolve(
            "stable", "3.14", Array.Empty<string>(),
            edgeExists: false, fallbackMode: true, fallbackRef: "v2.5.0", preAlphaRef: "edge");

        Assert.Equal("v2.5.0", result?.EffectiveRef);
    }

    [Fact]
    public void UnknownChannel_FallsBackToEdge()
    {
        var result = UpdateResolver.Resolve(
            "bogus", "4.0", Array.Empty<string>(),
            edgeExists: false, fallbackMode: false, fallbackRef: "", preAlphaRef: "edge");

        Assert.Equal("edge", result?.EffectiveRef);
    }
}

public class DowngradeGuardTests
{
    [Fact]
    public void BlocksOlderFinalTagWithoutAllowDowngrade() =>
        Assert.False(DowngradeGuard.Allows("4.0", "v3.14", allowDowngrade: false));

    [Fact]
    public void AllowsOlderFinalTagWhenAllowDowngradeSet() =>
        Assert.True(DowngradeGuard.Allows("4.0", "v3.14", allowDowngrade: true));

    [Fact]
    public void EdgeIsAlwaysAllowedRegardlessOfVersion() =>
        Assert.True(DowngradeGuard.Allows("4.0", "edge", allowDowngrade: false));

    [Fact]
    public void AllowsNewerOrEqualFinalTag() =>
        Assert.True(DowngradeGuard.Allows("3.14", "v4.0", allowDowngrade: false));

    // A custom --ref value (e.g. "test-prealpha") has no leading digit, so
    // tag_base_version leaves it unchanged -- it must never be treated as
    // "version 0" and wrongly blocked as a downgrade.
    [Fact]
    public void AllowsArbitraryNonNumericRefWithoutAllowDowngrade() =>
        Assert.True(DowngradeGuard.Allows("4.0", "test-prealpha", allowDowngrade: false));
}
