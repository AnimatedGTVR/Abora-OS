using DowngradeGuard;

const string Usage = "usage: downgrade-guard [--allow-downgrade] <current-version> <selected-ref>";

var rest = args.AsSpan();
var allowDowngrade = false;
if (rest.Length > 0 && rest[0] == "--allow-downgrade")
{
    allowDowngrade = true;
    rest = rest[1..];
}
if (rest.Length != 2)
{
    Console.Error.WriteLine(Usage);
    return 2;
}

if (Guard.Allows(rest[0], rest[1], allowDowngrade))
{
    Console.WriteLine("allow");
    return 0;
}
Console.WriteLine("block");
return 1;
