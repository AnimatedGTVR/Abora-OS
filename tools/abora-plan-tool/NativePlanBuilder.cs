using System.Text.Json;

namespace AboraPlanTool;

public sealed record BuildResult(string? PlanJson, string? Error);

/// Port of anix.sh's native_plan_from_file() -- turns ANIX Native syntax
/// (one `set`/`enable`/`disable`/`package add|remove` command per line) into
/// Plan JSON. The bash original built this up via one `jq -nc` call per
/// operation plus one more to append it to the running array -- up to 2N+1
/// subprocess spawns for an N-line file. This does it in one pass with a
/// real JSON writer instead.
public static class NativePlanBuilder
{
    public static BuildResult Build(string content, string version)
    {
        using var stream = new MemoryStream();
        using (var writer = new Utf8JsonWriter(stream))
        {
            writer.WriteStartObject();
            WritePlanVersion(writer, version);
            writer.WriteString("language", "anix");
            writer.WriteStartArray("operations");

            var lineNumber = 0;
            foreach (var rawLine in content.Split('\n'))
            {
                lineNumber++;
                var line = rawLine.TrimStart();
                if (line.Length == 0 || line[0] == '#')
                {
                    continue;
                }

                var words = line.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
                var error = WriteOperation(writer, words);
                if (error is not null)
                {
                    return new BuildResult(null, $"{lineNumber}: {error}");
                }
            }

            writer.WriteEndArray();
            writer.WriteEndObject();
        }

        return new BuildResult(System.Text.Encoding.UTF8.GetString(stream.ToArray()), null);
    }

    private static void WritePlanVersion(Utf8JsonWriter writer, string version)
    {
        if (long.TryParse(version, out var numeric))
        {
            writer.WriteNumber("planVersion", numeric);
        }
        else
        {
            writer.WriteString("planVersion", version);
        }
    }

    /// Returns an error message (without the line number, which the caller
    /// adds) or null on success.
    private static string? WriteOperation(Utf8JsonWriter writer, string[] words)
    {
        var command = words.Length > 0 ? words[0] : "";
        switch (command)
        {
            case "set":
                if (words.Length != 3) return "usage: set <key> <value>";
                writer.WriteStartObject();
                writer.WriteString("op", "set");
                writer.WriteString("key", words[1]);
                writer.WriteString("value", words[2]);
                writer.WriteEndObject();
                return null;

            case "enable":
                if (words.Length != 2) return "usage: enable <feature>";
                writer.WriteStartObject();
                writer.WriteString("op", "enable");
                writer.WriteString("feature", words[1]);
                writer.WriteEndObject();
                return null;

            case "disable":
                if (words.Length != 2) return "usage: disable <feature>";
                writer.WriteStartObject();
                writer.WriteString("op", "disable");
                writer.WriteString("feature", words[1]);
                writer.WriteEndObject();
                return null;

            case "package":
                if (words.Length != 3) return "usage: package <add|remove> <name>";
                if (words[1] != "add" && words[1] != "remove") return "package action must be add or remove";
                writer.WriteStartObject();
                writer.WriteString("op", words[1] == "add" ? "package.add" : "package.remove");
                writer.WriteString("name", words[2]);
                writer.WriteEndObject();
                return null;

            default:
                return $"unknown ANIX Native command: {command}";
        }
    }
}
