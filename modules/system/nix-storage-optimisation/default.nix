{
  # Regularly optimise nix store by replacing duplicates with hardlinks
  nix.optimise.automatic = true;

  # Remove older NixOS generations so old derivations can be gc'ed
  nix.gc = {
    automatic = true;
    # Trigger even if the system was powered down during the scheduled time
    persistent = true;
    dates = "weekly";
    # Delete all generation older than 30 days
    options = "--delete-older-than 30d";
  };
}
