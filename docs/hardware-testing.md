# Hardware Testing

Test release candidates on real hardware after VM checks pass.

## Coverage

Cover UEFI desktops and laptops, NVMe and SATA storage, Intel/AMD/NVIDIA graphics, Ethernet, Wi-Fi, Bluetooth, audio, suspend, brightness, and at least one multi-monitor setup when available.

## Test flow

1. Verify the ISO checksum and write it to known-good media.
2. Boot the live image and run `abora hardware-test --with-report`.
3. Confirm input, display, networking, storage detection, and installer startup.
4. Install without the USB target being selectable as the destination.
5. Reboot without the USB and test login, network, audio, graphics, suspend, update, and rollback.
6. Run `abora doctor`, `anix doctor`, and `tinypm doctor`.

Record the exact model, firmware mode, GPU, network hardware, edition, and result. For failures, save installer logs and create `abora support-report`. Review reports before sharing them.
