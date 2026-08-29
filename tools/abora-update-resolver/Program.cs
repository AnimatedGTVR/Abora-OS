namespace AboraUpdateResolver;

/// CLI entry point. Two subcommands, mirroring the two bash functions this
/// binary replaces (resolve_update_ref, guard_against_accidental_downgrade)
/// one-to-one so scripts/abora-update.sh's call sites barely have to
/// change: they just shell out here instead of running the logic inline.
/// All I/O (git ls-remote, reading VERSION, printing colored UI text) stays
/// in bash; this process only ever receives plain strings and returns a
/// plain result plus an exit code.
public static class Program
{
    private static int Main(string[] args)
    {
        if (args.Length == 0)
        {
            Console.Error.WriteLine("Usage: abora-update-resolver <resolve-ref|guard-downgrade> [options]");
            return 64; // EX_USAGE
        }

        try
        {
            return args[0] switch
            {
                "resolve-ref" => RunResolveRef(ParseFlags(args[1..])),
                "guard-downgrade" => RunGuardDowngrade(ParseFlags(args[1..])),
                var other => Unknown(other),
            };
        }
        catch (ArgParseException ex)
        {
            Console.Error.WriteLine(ex.Message);
            return 64; // EX_USAGE
        }
    }

    private static int Unknown(string command)
    {
        Console.Error.WriteLine($"Unknown command: {command}");
        return 64; // EX_USAGE
    }

    // resolve-ref --channel <c> --current-version <v> [--tags "<space separated>"]
    //             [--edge-exists] [--fallback-mode] [--fallback-ref <ref>]
    //             [--pre-alpha-ref <ref>]
    // Exit 0: prints "<effective_ref>\t<effective_ref_reason>" to stdout.
    // Exit 1: no ref could be resolved for the channel; nothing printed.
    private static int RunResolveRef(Flags flags)
    {
        var channel = flags.Require("--channel");
        var currentVersion = flags.Require("--current-version");
        var tags = flags.Get("--tags", "")
            .Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries)
            .ToList();
        var edgeExists = flags.Has("--edge-exists");
        var fallbackMode = flags.Has("--fallback-mode");
        var fallbackRef = flags.Get("--fallback-ref", "");
        var preAlphaRef = flags.Get("--pre-alpha-ref", "edge");

        var result = UpdateResolver.Resolve(
            channel, currentVersion, tags, edgeExists, fallbackMode, fallbackRef, preAlphaRef);

        if (result is null)
        {
            return 1;
        }

        Console.WriteLine($"{result.EffectiveRef}\t{result.EffectiveRefReason}");
        return 0;
    }

    // guard-downgrade --current-version <v> --selected-ref <ref> [--allow-downgrade]
    // Exit 0: update may proceed. Exit 2: blocked (would be a downgrade).
    private static int RunGuardDowngrade(Flags flags)
    {
        var currentVersion = flags.Require("--current-version");
        var selectedRef = flags.Require("--selected-ref");
        var allowDowngrade = flags.Has("--allow-downgrade");

        return DowngradeGuard.Allows(currentVersion, selectedRef, allowDowngrade) ? 0 : 2;
    }

    private static Flags ParseFlags(string[] args)
    {
        var values = new Dictionary<string, string>();
        var flagsSet = new HashSet<string>();

        for (var i = 0; i < args.Length; i++)
        {
            var arg = args[i];
            if (!arg.StartsWith("--"))
            {
                throw new ArgParseException($"Unexpected argument: {arg}");
            }

            // Boolean-style flags never consume the next token, even if a
            // value-looking string follows -- they're presence-only.
            if (arg is "--edge-exists" or "--fallback-mode" or "--allow-downgrade")
            {
                flagsSet.Add(arg);
                continue;
            }

            if (i + 1 >= args.Length)
            {
                throw new ArgParseException($"Missing value for {arg}");
            }

            values[arg] = args[++i];
        }

        return new Flags(values, flagsSet);
    }

    private sealed class ArgParseException(string message) : Exception(message);

    private sealed class Flags(Dictionary<string, string> values, HashSet<string> flagsSet)
    {
        public string Require(string name) =>
            values.TryGetValue(name, out var value)
                ? value
                : throw new ArgParseException($"Missing required option: {name}");

        public string Get(string name, string fallback) =>
            values.GetValueOrDefault(name, fallback);

        public bool Has(string name) => flagsSet.Contains(name);
    }
}
