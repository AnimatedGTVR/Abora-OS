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
                // Splitting on '\n' alone leaves a trailing '\r' on every
                // line of a CRLF-line-ended file. words.Split(null, ...)
                // below treats '\r' as whitespace and drops it for
                // enable/disable/package, but "set"'s 3-way split caps at 3
                // pieces, so its last piece is the untouched remainder of
                // the line -- the '\r' rode along inside the value
                // (`abora.hostname = "myhost\r";`) instead of being
                // stripped. TrimEnd('\r') only removes that specific
                // artifact, not other trailing whitespace, since a "set"
                // value like a gc.dates OnCalendar spec is allowed to keep
                // trailing/internal spacing verbatim (see WriteOperation).
                var line = rawLine.TrimStart().TrimEnd('\r');
                if (line.Length == 0 || line[0] == '#')
                {
                    continue;
                }

                var words = line.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
                var error = WriteOperation(writer, line, words);
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
    private static string? WriteOperation(Utf8JsonWriter writer, string line, string[] words)
    {
        var command = words.Length > 0 ? words[0] : "";
        switch (command)
        {
            case "set":
            {
                // Split into at most 3 parts (command, key, value) instead of
                // reusing the plain whitespace-tokenized `words` -- do_set
                // only bans '"', '\', and '${' for timezone/keyboard.xkb/
                // gc.days/gc.dates, so a legitimate value like a systemd
                // OnCalendar gc.dates spec ("Sun 03:00:00") contains a space
                // and must not be truncated the way `words.Length != 3` would.
                var parts = line.Split((char[]?)null, 3, StringSplitOptions.RemoveEmptyEntries);
                if (parts.Length != 3) return "usage: set <key> <value>";
                writer.WriteStartObject();
                writer.WriteString("op", "set");
                writer.WriteString("key", parts[1]);
                writer.WriteString("value", parts[2]);
                writer.WriteEndObject();
                return null;
            }

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
