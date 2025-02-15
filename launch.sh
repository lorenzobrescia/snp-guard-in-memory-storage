#!/bin/bash

#
# user changeable parameters
#
HDA=""
HDB=""
MEM="32768"
SMP="32"
CONSOLE="serial"
DAEMONIZE="0"
USE_VIRTIO="1"
DISCARD="none"
IP="192.168.122.100"
CPU_MODEL="EPYC-v4"
MONITOR_PATH=monitor
QEMU_CONSOLE_LOG=`pwd`/stdout.log
CERTS_PATH=

# linked to cli flag
ENABLE_ID_BLOCK=

SEV="0"
SEV_ES="0"
SEV_SNP="0"
USE_GDB="0"
KERNEL_HASHES="0"

SEV_TOOLCHAIN_PATH="build/snp-release/usr/local"
UEFI_PATH="$SEV_TOOLCHAIN_PATH/share/qemu/"
UEFI_CODE=""
UEFI_VARS=""

usage() {
	echo "$0 [options]"
	echo "Available <commands>:"
	echo " -sev               launch SEV guest"
	echo " -sev-es            launch SEV guest"
	echo " -sev-snp           launch SNP guest"
	echo " -enable-discard    for SNP, discard memory after conversion. (worse boot-time performance, but less memory usage)"
	echo " -bios              the bios to use (default $UEFI_PATH)"
	echo " -hda PATH          hard disk file (default $HDA)"
	echo " -hdb PATH          second hard disk file. Used for cloud-init config blob"
	echo " -mem MEM           guest memory size in MB (default $MEM)"
	echo " -smp NCPUS         number of virtual cpus (default $SMP)"
	echo " -cpu CPU_MODEL     QEMU CPU model/type to use (default $CPU_MODEL)."
	echo "                    You can also specify additional CPU flags, e.g. -cpu $CPU_MODEL,+avx512f,+avx512dq"
	echo " -kernel PATH       kernel to use"
	echo " -initrd PATH       initrd to use"
	echo " -kernel-hashes     verify kernel hashes"
	echo " -append ARGS       kernel command line arguments to use"
	echo " -cdrom PATH        CDROM image"
	echo " -default-network   enable default usermode networking"
	echo "                    (Requires that QEMU is built on a host that supports libslirp-dev 4.7 or newer)"
	echo " -ip IP             specify ip address in range 192.168.122.100 - 192.168.122.109 to use bridged network"
	echo " -daemonize         enable background execution of the VM"
	echo " -monitor PATH      Path to QEMU monitor socket (default: $MONITOR_PATH)"
	echo " -log PATH          Path to QEMU console log (default: $QEMU_CONSOLE_LOG)"
	echo " -certs PATH        Path to SNP certificate blob for guest (default: none)"
	echo " -id-block          Path to file with 96-byte, base64-encoded blob for the \"ID Block\" structure in SNP_LAUNCH_FINISH cmd"
	echo " -id-auth           Path to file with 4096-byte, base64 encoded blob for the \"ID Authentication Information\" structure in SNP_LAUNCH_FINISH"
	echo " -host-data         Path to file with 32-byte, base64 encoded blob for the \"HOST_DATA\" parameter in SNP_LAUNCH_FINISH"
	echo " -policy            Guest Policy. 0x prefixed string. For SEV-SNP default is 0x30000 and 0xb0000 enables the debug API. For SEV-ES the default is 0x5 and 0x4 enables the debug API."
	echo " -load-config PATH  Will load -bios,-smp,-kernel,-initrd,-append amd -policy from the VM config .toml file. You can still override this by passing the corresponding flag directly"
	exit 1
}

add_opts() {
	echo -n "$* " >> ${QEMU_CMDLINE}
}

exit_from_int() {
	rm -rf ${QEMU_CMDLINE}
	# restore the mapping
	stty intr ^c
	exit 1
}

run_cmd () {
	$*
	if [ $? -ne 0 ]; then
		echo "command $* failed"
		exit 1
	fi
}

get_cbitpos() {
	modprobe cpuid
	#
	# Get C-bit position directly from the hardware
	#   Reads of /dev/cpu/x/cpuid have to be 16 bytes in size
	#     and the seek position represents the CPUID function
	#     to read.
	#   The skip parameter of DD skips ibs-sized blocks, so
	#     can't directly go to 0x8000001f function (since it
	#     is not a multiple of 16). So just start at 0x80000000
	#     function and read 32 functions to get to 0x8000001f
	#   To get to EBX, which contains the C-bit position, skip
	#     the first 4 bytes (EAX) and then convert 4 bytes.
	#

	EBX=$(dd if=/dev/cpu/0/cpuid ibs=16 count=32 skip=134217728 | tail -c 16 | od -An -t u4 -j 4 -N 4 | sed -re 's|^ *||')
	CBITPOS=$((EBX & 0x3f))
}

trap exit_from_int SIGINT

#helper function to parse simple "key = value lines from a toml config file"
# ARG1 name of the toml key
# ARG2 path to toml file
# RESULT stored in global var PARSE_RESULT
PARSE_RESULT=""
parse_value_for_key() {
	key="$1"
	file="$2"
	# value=$(grep -Po "^\s*$key\s*=\s*(?:"\K[^"]*(?=")|\K[^"\s]+)" "$file")
	PARSE_RESULT=$(grep -Po "^\s*$key\s*=\s*(?:\"\K[^\"]*(?=\")|\K[^\"\s]+)" "$file")
}

if [ `id -u` -ne 0 ]; then
	echo "Must be run as root!"
	exit 1
fi

while [ -n "$1" ]; do
	case "$1" in
		-sev-snp)	SEV_SNP="1"
				SEV_ES="1"
				SEV="1"
				;;
		-enable-discard)
				DISCARD="both"
				;;
		-sev-es)	SEV_ES="1"
				SEV="1"
				;;
		-sev)		SEV="1"
				;;
		-hda) 		HDA="$2"
				shift
				;;
		-hdb) 		HDB="$2"
				shift
				;;
		-mem)  		MEM="$2"
				shift
				;;
		-smp)		SMP="$2"
				shift
				;;
		-cpu)		CPU_MODEL="$2"
				shift
				;;
		-bios)          UEFI_CODE="$2"
				shift
				;;
		-allow-debug)   ALLOW_DEBUG="1"
				;;
		-kernel)	KERNEL_FILE=$2
				shift
				;;
		-initrd)	INITRD_FILE=$2
				shift
				;;
		-kernel-hashes)
				KERNEL_HASHES="1"
				;;
		-append)	APPEND=$2
				shift
				;;
		-cdrom)		CDROM_FILE="$2"
				shift
				;;
		-default-network)
				USE_DEFAULT_NETWORK="1"
				;;
		-ip)		IP="$2"
				shift
				;;
		-daemonize)
				DAEMONIZE="1"
				;;
		-monitor)       MONITOR_PATH="$2"
				shift
				;;
		-log)           QEMU_CONSOLE_LOG="$2"
				shift
				;;
		-certs) CERTS_PATH="$2"
				shift
				;;
		-id-block) ID_BLOCK_FILE="$2"
				shift
				;;
		-id-auth) ID_AUTH_FILE="$2"    
			shift
			;;
		-host-data) HOST_DATA_FILE="$2"
			shift
			;;
		-policy) SEV_POLICY="$2"
			shift
			;;
		-vm-config-file) VM_CONFIG_FILE="$2"
			shift
			;;
		-load-config) TOML_CONFIG="$2"
			shift
			;;
 		*) 		usage
				;;
	esac

	shift
done

if [ -f "$TOML_CONFIG" ]; then
	echo "Parsing config options from file"
	if [ -z "$SMP" ]; then 
		parse_value_for_key "vcpu_count" "$TOML_CONFIG"
		SMP="$PARSE_RESULT"
	fi

	if [ -z "$UEFI_CODE" ]; then
	  parse_value_for_key "ovmf_file" "$TOML_CONFIG"
	  UEFI_CODE="$PARSE_RESULT"
	fi

	if [ -z "$KERNEL_FILE" ]; then
		parse_value_for_key "kernel_file" "$TOML_CONFIG"
	  KERNEL_FILE="$PARSE_RESULT"
	fi
	
	if [ -z "$INITRD_FILE" ]; then
		parse_value_for_key "initrd_file" "$TOML_CONFIG"
	  INITRD_FILE="$PARSE_RESULT"
	fi

	if [ -z "$APPEND" ]; then
		parse_value_for_key "kernel_cmdline" "$TOML_CONFIG"
	  APPEND="$PARSE_RESULT"
	fi

	if [ -z "$SEV_POLICY" ]; then
		parse_value_for_key "guest_policy" "$TOML_CONFIG"
	  SEV_POLICY="$PARSE_RESULT"
	fi

fi

TMP="$SEV_TOOLCHAIN_PATH/bin/qemu-system-x86_64"
QEMU_EXE="$(readlink -e $TMP)"
[ -z "$QEMU_EXE" ] && {
	echo "Can't locate qemu executable [$TMP]"
	usage
}

#Process -idblock and -auth block argument logic
if [[ -n "$ID_BLOCK_FILE" && -n "$ID_AUTH_FILE" ]]; then
	#This variable indicates that both id and auth block are present, so that
	#we dont have to do this length check again later on
	USE_ID_AND_AUTH=1
elif  [[ -n "$ID_BLOCK_FILE" || -n "$ID_AUTH_FILE" ]]; then
	echo "-id-block and -auth-block must either both bet set or both unset"
	exit 1
fi


[ -n "$HDA" ] && {
	TMP="$HDA"
	HDA="$(readlink -e $TMP)"
	[ -z "$HDA" ] && [ -z "$KERNEL_FILE" ] && {
		echo "Can't locate guest image file [$TMP]. Either specify image file or direct boot kernel"
		usage
	}

	GUEST_NAME="$(basename $TMP | sed -re 's|\.[^\.]+$||')"
}

[ -n "$CDROM_FILE" ] && {
	TMP="$CDROM_FILE"
	CDROM_FILE="$(readlink -e $TMP)"
	[ -z "$CDROM_FILE" ] && {
		echo "Can't locate CD-Rom file [$TMP]"
		usage
	}

	[ -z "$GUEST_NAME" ] && GUEST_NAME="$(basename $TMP | sed -re 's|\.[^\.]+$||')"
}


if [ -z "$UEFI_CODE" ]; then
	TMP="$UEFI_PATH/OVMF_CODE.fd"
	UEFI_CODE="$(readlink -e $TMP)"
	[ -z "$UEFI_CODE" ] && {
		echo "Can't locate UEFI code file [$TMP]"
		usage
	}

	[ -e "./$GUEST_NAME.fd" ] || {
		TMP="$UEFI_PATH/OVMF_VARS.fd"
		UEFI_VARS="$(readlink -e $TMP)"
		[ -z "$UEFI_VARS" ] && {
			echo "Can't locate UEFI variable file [$TMP]"
			usage
		}

		run_cmd "cp $UEFI_VARS ./$GUEST_NAME.fd"
	}
	UEFI_VARS="$(readlink -e ./$GUEST_NAME.fd)"
fi

if [ "$ALLOW_DEBUG" = "1" ]; then
	# This will dump all the VMCB on VM exit
	echo 1 > /sys/module/kvm_amd/parameters/dump_all_vmcbs

	# Enable some KVM tracing to the debug
	#echo kvm: >/sys/kernel/debug/tracing/set_event
	#echo kvm:* >/sys/kernel/debug/tracing/set_event
	#echo kvm:kvm_page_fault >/sys/kernel/debug/tracing/set_event
	#echo >/sys/kernel/debug/tracing/set_event
	#echo > /sys/kernel/debug/tracing/trace
	#echo 1 > /sys/kernel/debug/tracing/tracing_on
fi

# we add all the qemu command line options into a file
QEMU_CMDLINE=/tmp/cmdline.$$
rm -rf $QEMU_CMDLINE

add_opts "$QEMU_EXE"

# Basic virtual machine property
add_opts "-enable-kvm -cpu ${CPU_MODEL} -machine q35"

# add number of VCPUs
[ -n "${SMP}" ] && add_opts "-smp ${SMP},maxcpus=255"

# define guest memory
add_opts "-m ${MEM}M"
#luca: adding more slots in combination with maxmem allows to hotplug memory later on
#add_opts "-m ${MEM}M,slots=5,maxmem=$((${MEM} + 8192))M"

# don't reboot for SEV-ES guest
add_opts "-no-reboot"

# The OVMF binary, including the non-volatile variable store, appears as a
# "normal" qemu drive on the host side, and it is exposed to the guest as a
# persistent flash device.
if [ "${SEV_SNP}" = 1 ]; then
		add_opts "-bios ${UEFI_CODE}"
	if [ -n "$UEFI_VARS" ]; then
    	add_opts "-drive if=pflash,format=raw,unit=0,file=${UEFI_VARS}"
	fi
else
    add_opts "-drive if=pflash,format=raw,unit=0,file=${UEFI_CODE},readonly"
	if [ -n "$UEFI_VARS" ]; then
    	add_opts "-drive if=pflash,format=raw,unit=1,file=${UEFI_VARS}"
	fi
fi

# add CDROM if specified
[ -n "${CDROM_FILE}" ] && add_opts "-drive file=${CDROM_FILE},media=cdrom -boot d"

# NOTE: as of QEMU 7.2.0, libslirp-dev 4.7+ is needed, but fairly recent
# distros like Ubuntu 20.04 still only provide 4.1, so only enable
# usermode network if specifically requested.
if [ "$USE_DEFAULT_NETWORK" = "1" ]; then
    #echo "guest port 22 is fwd to host 8000..."
#    add_opts "-netdev user,id=vmnic,hostfwd=tcp::8000-:22 -device e1000,netdev=vmnic,romfile="
		add_opts " -netdev user,id=vmnic,hostfwd=tcp:127.0.0.1:2222-:22,hostfwd=tcp:127.0.0.1:8080-:80"
#    add_opts "-netdev user,id=vmnic"
    add_opts " -device virtio-net-pci,disable-legacy=on,iommu_platform=true,netdev=vmnic,romfile="
else
	add_opts "-netdev bridge,id=vmnic1,br=virbr0" 
	last_octet=${IP##*.}
	if [[ $last_octet -ge 100 && $last_octet -le 109 ]]; then
    	hex_offset=$(printf "%02X" $(( $last_octet - 100 + 0x56 )))
    	mac="52:54:00:12:34:$hex_offset"
		add_opts "-device virtio-net-pci,disable-legacy=on,iommu_platform=true,netdev=vmnic1,romfile=,mac=$mac"
	else
    	echo "Invalid IP: $IP. Must be between 192.168.122.100 and 192.168.122.109."
    	usage
	fi
fi

DISKS=( "$HDA" "$HDB" )
for ((i = 0; i < ${#DISKS[@]}; i++)); do
	DISK="${DISKS[i]}"
	#DISK might be "" if the clif flag was not set
	if [ -n "$DISK" ]; then
		if [ "$USE_VIRTIO" = "1" ]; then
			if [[ ${DISK} = *"qcow2" ]]; then
				add_opts "-drive file=${DISK},if=none,id=disk${i},format=qcow2"
			else
				add_opts "-drive file=${DISK},if=none,id=disk${i},format=raw"
			fi
			add_opts "-device virtio-scsi-pci,id=scsi${i},disable-legacy=on,iommu_platform=true"
			add_opts "-device scsi-hd,drive=disk${i},bootindex=$((i+1))"
		else
			if [[ ${DISK} = *"qcow2" ]]; then
				add_opts "-drive file=${DISK},format=qcow2"
			else
				add_opts "-drive file=${DISK},format=raw"
			fi
		fi
	fi
done

# If this is SEV guest then add the encryption device objects to enable support
if [ ${SEV} = "1" ]; then
	add_opts "-machine memory-encryption=sev0,vmport=off" 
	get_cbitpos

	if [[ -z "$SEV_POLICY" ]]; then 
		echo "-policy argument is mandatory"
		exit 1
	fi

	if [[ "$SEV_POLICY" != 0x* ]]; then
		echo "string passed to -policy must start with 0x"
		exit 1
	fi

	if [ "${SEV_SNP}" = 1 ]; then
		add_opts "-object memory-backend-memfd,id=ram1,size=${MEM}M,share=true,prealloc=false"
		add_opts "-machine memory-backend=ram1"

		#base set of options, that we always want to use
		#the following if statements might add some more options, depending on config flags
		SNP_OPTS_BUILDER="-object sev-snp-guest,id=sev0,policy=${SEV_POLICY},cbitpos=${CBITPOS},reduced-phys-bits=1"

		if [ -n "$CERTS_PATH" ]; then
			SNP_OPTS_BUILDER+=",certs-path=${CERTS_PATH}"
		fi

		if [ -n "$USE_ID_AND_AUTH" ]; then
			SNP_OPTS_BUILDER+=",id-block=$(cat $ID_BLOCK_FILE),id-auth=$(cat $ID_AUTH_FILE),auth-key-enabled=true"
		fi

		if [ -n "$HOST_DATA_FILE" ]; then
			SNP_OPTS_BUILDER+=",host-data=$(cat $HOST_DATA_FILE)"
		fi

		if [ ${KERNEL_FILE} ] && [ ${INITRD_FILE} ] && [ "${KERNEL_HASHES}" = 1 ]; then
			SNP_OPTS_BUILDER+=",kernel-hashes=on"
		fi

		add_opts ${SNP_OPTS_BUILDER}
	else # SEV_SNP = 0
		add_opts "-object sev-guest,id=sev0,policy=${SEV_POLICY},cbitpos=${CBITPOS},reduced-phys-bits=1"
	fi
fi # of if SEV = 1

# if -kernel arg is specified then use the kernel provided in command line for boot
if [ "${KERNEL_FILE}" != "" ]; then
	add_opts "-kernel $KERNEL_FILE"
	if [ -n "$APPEND" ]; then
		add_opts "-append \"$APPEND\""
	fi
	[ -n "${INITRD_FILE}" ] && add_opts "-initrd ${INITRD_FILE}"
fi

# disable graphical interface
add_opts "-vga none"

if [ "${DAEMONIZE}" = "0" ]; then
	if [ "${CONSOLE}" = "serial" ]; then
		add_opts "-nographic"
	fi
else	
	add_opts "-daemonize"
fi

# start monitor on pty and named socket 'monitor'
# add_opts "-monitor pty -monitor unix:${MONITOR_PATH},server,nowait"

# add_opts "-qmp tcp:localhost:4444,server,wait=off"

# save the command line args into log file
cat $QEMU_CMDLINE | tee ${QEMU_CONSOLE_LOG}
echo | tee -a ${QEMU_CONSOLE_LOG}

#touch /tmp/events
#add_opts "-trace events=/tmp/events"

echo "Disabling transparent huge pages"
echo "never" | sudo tee /sys/kernel/mm/transparent_hugepage/enabled


# map CTRL-C to CTRL ]
echo "Mapping CTRL-C to CTRL-]"
stty intr ^]

echo "Launching VM ..."
echo "  $QEMU_CMDLINE"
sleep 1
bash ${QEMU_CMDLINE}  2>&1 | tee -a ${QEMU_CONSOLE_LOG}

# restore the mapping
stty intr ^c

rm -rf ${QEMU_CMDLINE}
