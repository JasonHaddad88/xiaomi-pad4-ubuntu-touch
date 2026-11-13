# Nura on clover (Adreno 512): graphics settings for a smooth interface.
# Installed as /etc/profile.d/zz-nura-graphics.sh; it sorts after
# sdm660-adreno-quirks.sh, which sets FD_MESA_DEBUG=noblit.
# Background and measurements: device-fixes/nura/graphics-smoothness/README.md
#
# The compositor (phoc) and the apps need different settings:
# - phoc keeps FD_MESA_DEBUG=noblit. It is faster with tiled rendering.
# - The shell and the apps get the settings below. They are started under
#   nura-session, which phosh-session runs in place of gnome-session
#   (PHOSH_SESSION_BIN) and which sets NURA_SESSION. gnome-session reads
#   /etc/profile again, so the values have to be set here, not in the wrapper.
#
# sysmem:    render straight to the buffer instead of tile by tile (GMEM).
# gradients: GTK4 does not supersample gradients.
if [ -n "$NURA_SESSION" ]; then
	export FD_MESA_DEBUG=noblit,sysmem
	export GSK_GPU_DISABLE=gradients
elif [ -x /usr/local/bin/nura-session ]; then
	export PHOSH_SESSION_BIN=/usr/local/bin/nura-session
fi
