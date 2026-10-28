#!/system/bin/sh
# magisk-compatible shim: forwards to our su
case "$1" in
  su)
    shift
    exec /system/bin/su "$@"
    ;;
  -v|--version|version)
    echo "26.4:MAGISK"
    exit 0
    ;;
  *)
    echo "26.4:MAGISK"
    exit 0
    ;;
esac
