#!/usr/bin/env bash
# Seed the Vulkan translation layers Nix already fetched, so the download loops
# in functions_helper find them present and skip the fetch. They are copied in
# as a symlink farm rather than symlinked wholesale because PortProton creates
# its DXVK shader cache inside these directories.
for pw_nix_bundle in @runtime@/VULKAN/* ; do
    pw_nix_target="${PW_VULKAN_DIR}/${pw_nix_bundle##*/}"
    [[ -e "${pw_nix_target}" ]] && continue
    # Resolve first: cp would otherwise copy the store symlink itself.
    if cp -rs "$(readlink -f "${pw_nix_bundle}")" "${pw_nix_target}" ; then
        find "${pw_nix_target}" -type d -exec chmod u+w {} +
    fi
done
unset pw_nix_bundle pw_nix_target
