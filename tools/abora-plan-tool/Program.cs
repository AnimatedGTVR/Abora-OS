namespace AboraPlanTool;

/// CLI entry point. `parse` reads a Plan JSON document from stdin, does the
/// structural validation described in PlanParser, and on success prints one
/// line per operation for the caller (scripts/anix.sh) to iterate over
/// without shelling out to jq per field per operation. All ANIX-specific
/// business rules that must stay a single source of truth with other
/// commands (feature_to_anix_key, do_set's per-key value validation) are
/// the caller's job -- see PlanParser's doc comment.
public static class Program
{
    private static int Main(string[] args)
    {
        if (args.Length == 0 || (args[0] != "parse" && args[0] != "build-native"))
        {
            Console.Error.WriteLine("Usage: abora-plan-tool <parse|build-native> --expected-version <version>");
            return 64; // EX_USAGE
        }

        string? expectedVersion = null;
        for (var i = 1; i < args.Length; i++)
        {
            if (args[i] == "--expected-version" && i + 1 < args.Length)
            {
                expectedVersion = args[++i];
            }
        }

        if (expectedVersion is null)
        {
            Console.Error.WriteLine("Missing required option: --expected-version");
            return 64; // EX_USAGE
        }

        return args[0] == "parse" ? RunParse(expectedVersion) : RunBuildNative(expectedVersion);
    }

    private static int RunParse(string expectedVersion)
    {
        var json = Console.In.ReadToEnd();
        var result = PlanParser.Parse(json, expectedVersion);

        if (!result.Success)
        {
            foreach (var error in result.Errors)
            {
                Console.Error.WriteLine(error);
            }
            return 1;
        }

        var plan = result.Plan!;
        Console.WriteLine($"language\t{plan.Language}");
        foreach (var op in plan.Operations)
        {
            Console.WriteLine($"{op.Op}\t{op.Field1}\t{op.Field2}");
        }
        return 0;
    }

    private static int RunBuildNative(string expectedVersion)
    {
        var content = Console.In.ReadToEnd();
        var result = NativePlanBuilder.Build(content, expectedVersion);

        if (result.Error is not null)
        {
            Console.Error.WriteLine(result.Error);
            return 1;
        }

        Console.WriteLine(result.PlanJson);
        return 0;
    }
}
