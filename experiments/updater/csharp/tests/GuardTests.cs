using DowngradeGuard;

// Runs from the implementation directory (the Labs stage cwd), so ../shared is the spec.
var failures = 0;

void Report(bool ok, string name)
{
    if (!ok)
    {
        failures++;
    }
    Console.WriteLine($"LABS-TEST: {(ok ? "PASS" : "FAIL")} {name}");
}

static List<string[]> ReadCases(string name, int fields)
{
    var path = Path.Combine("..", "shared", name);
    var cases = new List<string[]>();
    var lineNumber = 0;
    foreach (var line in File.ReadLines(path))
    {
        lineNumber++;
        if (string.IsNullOrWhiteSpace(line) || line.StartsWith('#'))
        {
            continue;
        }
        var row = line.Split('\t');
        if (row.Length != fields)
        {
            throw new InvalidDataException($"{path}:{lineNumber}: expected {fields} tab-separated fields, got {row.Length}");
        }
        cases.Add(row);
    }
    if (cases.Count == 0)
    {
        throw new InvalidDataException($"{path} has no cases");
    }
    return cases;
}

foreach (var row in ReadCases("tag-base-cases.tsv", 2))
{
    var got = Guard.TagBaseVersion(row[0]);
    Report(got == row[1], $"TagBaseVersion(\"{row[0]}\") = \"{got}\", want \"{row[1]}\"");
}

foreach (var row in ReadCases("downgrade-cases.tsv", 4))
{
    var got = Guard.Allows(row[0], row[1], row[2] == "yes");
    Report(got == (row[3] == "allow"), $"{row[0]} -> {row[1]} allow_downgrade={row[2]}: {(got ? "allow" : "block")}");
}

return failures == 0 ? 0 : 1;
