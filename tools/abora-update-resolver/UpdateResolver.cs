using System.Text.RegularExpressions;

namespace AboraUpdateResolver;

public sealed record ResolveResult(string EffectiveRef, string EffectiveRefReason);

/// Port of resolve_update_ref() from scripts/abora-update.sh. All I/O
/// (git ls-remote for tags/branch existence) stays in bash -- this takes
/// the results as plain inputs and only makes the decision, which is the
/// part that was genuinely painful as nested bash case/pipeline logic.
public static class UpdateResolver
{
    /// Returns null if no ref could be resolved for the channel (mirrors
    /// resolve_update_ref's final `return 1` path) -- the caller (bash)
    /// already knows how to print "Could not resolve an Abora update ref
    /// for channel '...'" itself.
    public static ResolveResult? Resolve(
        string channel,
        string currentVersion,
        IReadOnlyList<string> tags,
        bool edgeExists,
        bool fallbackMode,
        string fallbackRef,
        string preAlphaRef)
    {
        if (fallbackMode)
        {
            return new ResolveResult(fallbackRef, "explicit fallback requested");
        }

        switch (channel)
        {
            case "pre-alpha":
            case "prealpha":
                return new ResolveResult(preAlphaRef, "pre-alpha build requested explicitly");

            case "unstable":
                return new ResolveResult("edge", "unstable channel tracks edge");

            case "demo":
            case "dev":
                return ResolveDemoChannel(tags, currentVersion);

            case "stable":
            case "":
                return ResolveStableChannel(tags, currentVersion, edgeExists);

            default:
                // Bash prints the "Unknown channel" warning itself before
                // calling us, since that's UI output, not a decision.
                return new ResolveResult("edge", "unknown channel fallback to edge");
        }
    }

    private static ResolveResult? ResolveDemoChannel(IReadOnlyList<string> tags, string currentVersion)
    {
        var demoTags = tags.Where(VersionUtil.IsDemoReleaseTag).ToList();
        var demoTag = VersionUtil.LatestTag(MatchingCurrentVersionLine(demoTags, currentVersion))
                      ?? VersionUtil.LatestTag(demoTags);

        return demoTag is not null
            ? new ResolveResult(demoTag, "demo channel selected latest demo/dev tag")
            : null;
    }

    private static ResolveResult? ResolveStableChannel(
        IReadOnlyList<string> tags, string currentVersion, bool edgeExists)
    {
        if (tags.Count == 0 && edgeExists)
        {
            return new ResolveResult("edge", "stable channel could not read release tags; using edge");
        }

        var finalTags = tags.Where(VersionUtil.IsFinalReleaseTag).ToList();

        var finalTag = VersionUtil.LatestTag(
            finalTags.Where(tag => !VersionUtil.VersionLessThan(VersionUtil.TagBaseVersion(tag), currentVersion)));
        if (finalTag is not null)
        {
            return new ResolveResult(finalTag, "stable channel selected latest final tag not older than installed version");
        }

        var demoTags = tags.Where(VersionUtil.IsDemoReleaseTag).ToList();
        var demoTag = VersionUtil.LatestTag(MatchingCurrentVersionLine(demoTags, currentVersion));
        if (demoTag is not null)
        {
            return new ResolveResult(demoTag, "stable channel found no final tag for this release line; using matching demo/dev tag");
        }

        var olderTag = VersionUtil.LatestTag(finalTags);
        if (olderTag is not null)
        {
            return new ResolveResult("edge", "stable channel has no final tag newer than installed version; using edge");
        }

        return null;
    }

    /// Mirrors `awk -v cur="$current_version" 'NF && $0 ~ ("^v?" cur) { print }'`
    /// -- current_version is used unescaped as a regex fragment, exactly as
    /// the original awk did (a literal "." in a version string matches any
    /// character there, same as the bash original).
    private static IEnumerable<string> MatchingCurrentVersionLine(IEnumerable<string> tags, string currentVersion)
    {
        var pattern = new Regex("^v?" + currentVersion);
        return tags.Where(tag => tag.Length > 0 && pattern.IsMatch(tag));
    }
}
