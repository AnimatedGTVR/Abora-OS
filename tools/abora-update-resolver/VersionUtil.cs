using System.Text.RegularExpressions;

namespace AboraUpdateResolver;

/// Ports of the pure string/version helpers from scripts/abora-update.sh
/// (tag_base_version, is_final_release_tag, is_demo_release_tag,
/// version_lt, latest_tag_from_list) -- kept behaviorally identical to
/// their bash originals so this binary is a drop-in replacement for the
/// decision logic, not a reinterpretation of it.
public static class VersionUtil
{
    private static readonly Regex LeadingNumericRegex =
        new(@"^([0-9]+(?:\.[0-9]+)*)", RegexOptions.Compiled);

    private static readonly Regex FinalReleaseTagRegex =
        new(@"^v[0-9]+(?:\.[0-9]+)*$", RegexOptions.Compiled);

    private static readonly Regex DemoReleaseTagRegex =
        new(@"^v?[0-9]+(?:\.[0-9]+)*.*(ALPHA|Alpha|alpha|DEMO|Demo|demo|Dev|dev|Pre|pre|RC|Rc|rC|rc).*$",
            RegexOptions.Compiled);

    /// Mirrors tag_base_version(): strips a leading "v" and any trailing
    /// non-numeric suffix, leaving just the dotted numeric version (e.g.
    /// "v4.1-DEMO2" -> "4.1"). If the string doesn't start with a digit at
    /// all, sed's original no-match-means-unchanged behavior is replicated
    /// by returning the (v-stripped) input as-is.
    public static string TagBaseVersion(string tag)
    {
        var stripped = tag.StartsWith('v') ? tag[1..] : tag;
        var match = LeadingNumericRegex.Match(stripped);
        return match.Success ? match.Groups[1].Value : stripped;
    }

    public static bool IsFinalReleaseTag(string tag) => FinalReleaseTagRegex.IsMatch(tag);

    public static bool IsDemoReleaseTag(string tag) => DemoReleaseTagRegex.IsMatch(tag);

    /// Dotted-numeric version comparison. Most callers of version_lt in
    /// abora-update.sh compare tag_base_version() output or the raw VERSION
    /// file contents -- plain dotted-numeric strings, where an element-wise
    /// numeric comparison is an exact match for `sort -V`. But
    /// guard_against_accidental_downgrade can also be asked to compare an
    /// arbitrary non-numeric ref (e.g. a custom --ref value like
    /// "test-prealpha", which tag_base_version leaves unchanged since it
    /// has no leading digit at all) -- `sort -V` always sorts such a string
    /// *after* any numeric version ("4.0" sorts before "test-prealpha"), so
    /// that case is handled explicitly rather than letting a naive
    /// segment-wise parse silently treat it as version "0" and wrongly
    /// report it as older than everything.
    public static int CompareDottedVersions(string a, string b)
    {
        var aNumeric = IsNumericVersion(a);
        var bNumeric = IsNumericVersion(b);

        if (aNumeric != bNumeric)
        {
            return aNumeric ? -1 : 1;
        }

        if (!aNumeric)
        {
            return string.CompareOrdinal(a, b);
        }

        var aParts = a.Split('.');
        var bParts = b.Split('.');
        var len = Math.Max(aParts.Length, bParts.Length);
        for (var i = 0; i < len; i++)
        {
            var av = i < aParts.Length ? int.Parse(aParts[i]) : 0;
            var bv = i < bParts.Length ? int.Parse(bParts[i]) : 0;
            if (av != bv) return av.CompareTo(bv);
        }
        return 0;
    }

    private static bool IsNumericVersion(string s) =>
        s.Length > 0 && s.Split('.').All(part => int.TryParse(part, out _));

    public static bool VersionLessThan(string a, string b) =>
        a != b && CompareDottedVersions(a, b) < 0;

    /// Mirrors `sort -V | tail -n1` over a set of tags. Tags compare first
    /// by their dotted-numeric base version (matching sort -V exactly for
    /// the common case), then fall back to ordinal string comparison to
    /// deterministically break ties between same-version suffixed tags
    /// (e.g. two demo tags for the same release line). This is a
    /// documented, tested simplification of full GNU sort -V semantics --
    /// not a byte-exact port -- sufficient because every real caller either
    /// compares suffix-free final tags (where this is exact) or has at most
    /// one candidate per version line in practice.
    public static string? LatestTag(IEnumerable<string> tags)
    {
        string? best = null;
        foreach (var tag in tags)
        {
            if (best is null || CompareTags(tag, best) > 0)
            {
                best = tag;
            }
        }
        return best;
    }

    private static int CompareTags(string a, string b)
    {
        var cmp = CompareDottedVersions(TagBaseVersion(a), TagBaseVersion(b));
        return cmp != 0 ? cmp : string.CompareOrdinal(a, b);
    }
}
