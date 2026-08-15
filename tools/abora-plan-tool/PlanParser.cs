using System.Text.Json;

namespace AboraPlanTool;

public sealed record PlanOperation(string Op, string Field1, string Field2);

public sealed record ParsedPlan(string Language, IReadOnlyList<PlanOperation> Operations);

public sealed record ParseResult(ParsedPlan? Plan, IReadOnlyList<string> Errors)
{
    public bool Success => Plan is not null;
}

/// Port of anix.sh's validate_plan_json() -- but only the parts that are
/// genuinely about JSON *shape* (well-formed JSON, planVersion, the
/// operations array, which fields each op type requires, the fixed "set"
/// key allowlist, and package-name syntax). Two things stay in bash on
/// purpose, not because C# can't do them, but because bash already treats
/// them as a single source of truth shared with other commands:
///
///   - enable/disable feature names are resolved through
///     feature_to_anix_key(), shared with `anix enable`/`anix disable`
///     (do_toggle) and do_diff_plan. This tool extracts the raw feature
///     string but does not validate it -- an unrecognized feature comes
///     back from feature_to_anix_key() as empty/failure in bash exactly
///     the same way an empty .feature field does here, so bash's existing
///     check covers both cases without this tool needing its own copy of
///     that mapping.
///   - what a "set" value must look like beyond being present (hostname
///     regex, desktop/wallpaper validity, shell enum, etc.) stays in
///     do_set, which this tool's caller still runs for every operation.
public static class PlanParser
{
    private static readonly HashSet<string> SetKeyAllowlist = new(StringComparer.Ordinal)
    {
        "hostname", "timezone", "keyboard", "keyboard.console", "keyboard.xkb",
        "desktop", "wallpaper", "shell", "gc.days", "garbageCollect.dates", "gc.dates",
    };

    public static ParseResult Parse(string json, string expectedVersion)
    {
        JsonDocument doc;
        try
        {
            doc = JsonDocument.Parse(json);
        }
        catch (JsonException)
        {
            return new ParseResult(null, ["Plan is not valid JSON."]);
        }

        using (doc)
        {
            var root = doc.RootElement;
            if (root.ValueKind != JsonValueKind.Object)
            {
                return new ParseResult(null, ["Plan is not valid JSON."]);
            }

            var version = ReadPlanVersion(root);
            if (version != expectedVersion)
            {
                return new ParseResult(null,
                    [$"Unsupported plan version: '{(version.Length == 0 ? "missing" : version)}' (expected {expectedVersion})."]);
            }

            if (!root.TryGetProperty("operations", out var opsElement) || opsElement.ValueKind != JsonValueKind.Array)
            {
                return new ParseResult(null, ["Plan is missing an 'operations' array."]);
            }

            var language = root.TryGetProperty("language", out var langElement) && langElement.ValueKind == JsonValueKind.String
                ? langElement.GetString() ?? ""
                : "";

            var errors = new List<string>();
            var operations = new List<PlanOperation>();
            var index = 0;
            foreach (var entry in opsElement.EnumerateArray())
            {
                ParseOperation(entry, index, operations, errors);
                index++;
            }

            return errors.Count == 0
                ? new ParseResult(new ParsedPlan(language, operations), [])
                : new ParseResult(null, errors);
        }
    }

    private static string ReadPlanVersion(JsonElement root)
    {
        if (!root.TryGetProperty("planVersion", out var versionElement))
        {
            return "";
        }

        return versionElement.ValueKind switch
        {
            JsonValueKind.String => versionElement.GetString() ?? "",
            JsonValueKind.Number => versionElement.GetRawText(),
            _ => "",
        };
    }

    private static void ParseOperation(JsonElement entry, int index, List<PlanOperation> operations, List<string> errors)
    {
        var op = GetString(entry, "op");

        switch (op)
        {
            case "set":
            {
                var key = GetString(entry, "key");
                var value = GetString(entry, "value");
                if (!SetKeyAllowlist.Contains(key))
                {
                    errors.Add($"operation {index}: unknown set key '{key}'");
                }
                if (value.Length == 0)
                {
                    errors.Add($"operation {index}: set requires a value");
                }
                operations.Add(new PlanOperation(op, key, value));
                break;
            }
            case "enable":
            case "disable":
            {
                var feature = GetString(entry, "feature");
                operations.Add(new PlanOperation(op, feature, ""));
                break;
            }
            case "package.add":
            case "package.remove":
            {
                var name = GetString(entry, "name");
                if (!IsValidPackageName(name))
                {
                    errors.Add($"operation {index}: invalid package name '{name}'");
                }
                operations.Add(new PlanOperation(op, name, ""));
                break;
            }
            default:
                errors.Add($"operation {index}: unknown op '{op}'");
                break;
        }
    }

    private static string GetString(JsonElement entry, string property)
    {
        if (entry.ValueKind != JsonValueKind.Object) return "";
        if (!entry.TryGetProperty(property, out var value)) return "";
        return value.ValueKind == JsonValueKind.String ? value.GetString() ?? "" : "";
    }

    private static bool IsValidPackageName(string name) =>
        name.Length > 0 && name.All(c => char.IsAsciiLetterOrDigit(c) || c is '.' or '_' or '+' or '-');
}
