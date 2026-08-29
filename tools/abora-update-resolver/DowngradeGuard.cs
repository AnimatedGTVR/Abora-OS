namespace AboraUpdateResolver;

/// Port of guard_against_accidental_downgrade() from scripts/abora-update.sh.
public static class DowngradeGuard
{
    /// True if the update is allowed to proceed; false means it would be an
    /// accidental downgrade and should be blocked (bash prints its own
    /// detailed abora_error block, since that's UI, not a decision).
    public static bool Allows(string currentVersion, string selectedRef, bool allowDowngrade)
    {
        if (selectedRef == "edge" || allowDowngrade)
        {
            return true;
        }

        var selectedVersion = VersionUtil.TagBaseVersion(selectedRef);
        return !VersionUtil.VersionLessThan(selectedVersion, currentVersion);
    }
}
