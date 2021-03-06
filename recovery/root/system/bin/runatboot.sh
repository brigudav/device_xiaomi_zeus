#!/sbin/sh

# The below variables shouldn't need to be changed
# unless you want to call the script something else
SCRIPTNAME="load_modules"
LOGFILE=/tmp/recovery.log

# Set default log level
DEFAULT_LOGLEVEL=1
# 0 Errors only
# 1 Errors and Information
# 2 Errors, Information, and Debugging
CUSTOM_LOGLEVEL=$(getprop $SCRIPTNAME.loglevel)
if [ -n "$CUSTOM_LOGLEVEL" ]; then
    __VERBOSE="$CUSTOM_LOGLEVEL"
else
    __VERBOSE="$DEFAULT_LOGLEVEL"
fi

# Exit codes:
# 0 Success
# 1 Unknown encryption type
# 2 Temp Mount Failure

# Function for logging to the recovery log
log_print()
{
	# 0 = Error; 1 = Information; 2 = Debugging
	case $1 in
		0|error)
			LOG_LEVEL="E"
			;;
		1|info)
			LOG_LEVEL="I"
			;;
		2|debug)
			LOG_LEVEL="DEBUG"
			;;
		*)
			LOG_LEVEL="UNKNOWN"
			;;
	esac
	if [ $__VERBOSE -ge "$1" ]; then
		echo "$LOG_LEVEL:$SCRIPTNAME::$2" >> "$LOGFILE"
	fi
}

finish()
{
	umount "$TEMPVEN"
	$setprop_bin $SCRIPTNAME.vendor_mounted 0
	rmdir "$TEMPVEN"
	log_print 1 "$SCRIPTNAME complete."
	exit 0
}

check_fastboot_boot()
{
	is_fastboot_boot=$(getprop ro.boot.fastboot)
	twrpfastboot=$(grep twrpfastboot /proc/cmdline)
	if [ -n "$is_fastboot_boot" ]; then
		log_print 2 "Fastboot boot detected. ro.boot.fastboot=$is_fastboot_boot"
	elif [ -z "$is_fastboot_boot" ] && [ -n "$twrpfastboot" ]; then
		log_print 2 "twrpfastboot flag found. Setting ro.boot.fastboot..."
		$setprop_bin ro.boot.fastboot 1
		is_fastboot_boot=$(getprop ro.boot.fastboot)
		log_print 2 "ro.boot.fastboot=$is_fastboot_boot"
	else
		log_print 2 "Recovery mode boot detected."
	fi
}

check_resetprop()
{
	if [ -e /system/bin/resetprop ] || [ -e /sbin/resetprop ]; then
		log_print 2 "Resetprop binary found!"
		setprop_bin=resetprop
	else
		log_print 2 "Resetprop binary not found. Falling back to setprop."
		setprop_bin=setprop
	fi
}

check_dynamic()
{
	dynamic_partitions=$(getprop ro.boot.dynamic_partitions)
	if [ "$dynamic_partitions" = "true" ]; then
		unset suffix
	fi
}

temp_mount()
{
	mkdir "$1"
	if [ -d "$1" ]; then
		log_print 2 "Temporary $2 folder created at $1."
	else
		log_print 0 "Unable to create temporary $2 folder."
		finish_error
	fi
	mount -t ext4 -o ro "$3" "$1"
	if [ -n "$(ls -A "$1" 2>/dev/null)" ]; then
		log_print 2 "$2 mounted at $1."
		$setprop_bin $SCRIPTNAME."$2"_mounted 1
		log_print 2 "$SCRIPTNAME.$2_mounted=$(getprop "$SCRIPTNAME"."$2"_mounted)"
	else
		log_print 0 "Unable to mount $2 to temporary folder."
		finish_error
	fi
}

load_module()
{
	is_module_loaded=$(lsmod | grep "$1")
	if [ -n "$is_module_loaded" ]; then
		log_print 2 "$1 module already loaded. Proceeding..."
	else
		insmod "$TEMPVEN"/lib/modules/"$1".ko
		log_print 2 "Loaded $1 module."        
	fi
}

log_print 2 "Running $SCRIPTNAME script for TWRP..."
check_resetprop
check_fastboot_boot

ab_device=$(getprop ro.build.ab_update)

if [ -n "$ab_device" ]; then
	log_print 2 "A/B device detected! Finding current boot slot..."
	suffix=$(getprop ro.boot.slot_suffix)
	if [ -z "$suffix" ]; then
		suf=$(getprop ro.boot.slot)
		if [ -n "$suf" ]; then
			suffix="_$suf"
		fi
	fi
	log_print 2 "Current boot slot: $suffix"
fi

if [ -n "$is_fastboot_boot" ]; then
	log_print 1 "No module loading required. Exiting script."
	exit 0
else
	check_dynamic

	TEMPVEN=/v
	venpath="/dev/block/bootdevice/by-name/vendor$suffix"

	temp_mount "$TEMPVEN" "vendor" "$venpath"

  load_module "fts_touch_spi.ko"
  load_module "xiaomi_touch.ko"
  load_module "qti_battery_charger.ko"
  load_module "focaltech_fts.ko"
  load_module "adsp_loader_dlkm.ko"

	finish
fi
