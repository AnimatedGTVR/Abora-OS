using System.Text.RegularExpressions;

namespace DowngradeGuard;

// Spec: experiments/updater/shared/README.md
public static partial class Guard
{
    [GeneratedRegex(@"^([0-9]+(?:\.[0-9]+)*)")]
    private static partial Regex LeadingNumeric();

    /// Strips one leading "v" and any non-numeric suffix ("v4.1-DEMO2" -> "4.1").
    public static string TagBaseVersion(string tag)
    {
        var stripped = tag.StartsWith('v') ? tag[1..] : tag;
        var match = LeadingNumeric().Match(stripped);
        return match.Success ? match.Groups[1].Value : stripped;
    }

    /// Returns the parsed parts, or null if any part is not a 32-bit decimal integer.
    private static int[]? NumericParts(string version)
    {
        if (version.Length == 0)
        {
            return null;
        }

        var fields = version.Split('.');
        var parts = new int[fields.Length];
        for (var i = 0; i < fields.Length; i++)
        {
            // int.TryParse alone would accept "+1", " 1" and "-1"; the spec only allows digits.
            if (fields[i].Length == 0 || !fields[i].All(char.IsAsciiDigit) || !int.TryParse(fields[i], out parts[i]))
            {
                return null;
            }
        }
        return parts;
    }

    /// Orders numeric versions before non-numeric refs.
    public static int CompareDottedVersions(string a, string b)
    {
        var aParts = NumericParts(a);
        var bParts = NumericParts(b);

        if ((aParts is null) != (bParts is null))
        {
            return aParts is not null ? -1 : 1;
        }
        if (aParts is null || bParts is null)
        {
            return Math.Sign(string.CompareOrdinal(a, b));
        }

        for (var i = 0; i < Math.Max(aParts.Length, bParts.Length); i++)
        {
            var av = i < aParts.Length ? aParts[i] : 0;
            var bv = i < bParts.Length ? bParts[i] : 0;
            if (av != bv)
            {
                return av.CompareTo(bv);
            }
        }
        return 0;
    }

    public static bool VersionLessThan(string a, string b) =>
        a != b && CompareDottedVersions(a, b) < 0;

    /// True if updating from currentVersion to selectedRef may proceed.
    public static bool Allows(string currentVersion, string selectedRef, bool allowDowngrade) =>
        selectedRef == "edge" || allowDowngrade ||
        !VersionLessThan(TagBaseVersion(selectedRef), currentVersion);
}
