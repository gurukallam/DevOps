#!/bin/bash
#-------------------------------------------------------------------------------
#
# TITLE:    Manage Packages on Red Hat Enterprise Linux RHEL
#
#-------------------------------------------------------------------------------
# AUTHOR:   Anitesh A. Lal
# DATE:     2013-10-09 (YYYY-MM-DD)
#-------------------------------------------------------------------------------
# PURPOSE: manage installed RPM packages using the existing YUM configuration.
#-------------------------------------------------------------------------------
# INPUT: optional command line arguments see: --help for details
#-------------------------------------------------------------------------------
# OUTPUT: Manages Packages on RHEL using the yum update command
#-------------------------------------------------------------------------------
# USAGE: see output of ./Manage_Packages_on_RHEL.sh --help
#-------------------------------------------------------------------------------
# ASSUMPTIONS:
# o  existing yum configuration is configured correctly
# o /tmp directory is writable & has space to log the output of this script
#-------------------------------------------------------------------------------
# EXIT STATUSES:
#   0 the requested task has been completed successfully
#  10 failed to parse commandline arguments
#  20 unhandled command line arguments
#  25 missing required command line argument
#  30 unsupported OS version
#  40 failed yum-complete-transaction (RHEL7 and RHEL6 only)
#  50 uid=0(root) required
#  55 failed to copy symlink $symlink to $copied_link
#  57 symlink $symlink is NOT a symlink failed to copy $copied_link
#  60 failed to create a backup of $symlink as $BACKUP
#  70 failed to relocate $symlink to $RELOCATE
#  80 failed to restore $BACKUP to $symlink
# 100 failed to generate installed RPM list
# 125 failed running: yum clean all
# 150 missing expected channel definition
# 180 Please reboot this server then try running this script again
# 200 RPM packages not up to date
# 250 reboot required
#-------------------------------------------------------------------------------
PATH="/usr/sbin:/sbin:/usr/bin:/bin"
IGNORE="/dev/null"

#-------------------------------------------------------------------------------
function    usage() {
#-------------------------------------------------------------------------------
# PURPOSE: display help information to briefly explain how to use this script
#-------------------------------------------------------------------------------
# INPUT: N/A
#-------------------------------------------------------------------------------
# OUTPUT: usage information for this script is printed to STDOUT
#-------------------------------------------------------------------------------
# ASSUMPTIONS: N/A
#-------------------------------------------------------------------------------
    'cat' <<USAGE
USAGE: $0  { --help | --sanity_check | --downloadonly | --update | --verify } \
[ --noyumclean ] [ --no-reboot ] [ --no_channel_verification ] \
[ --OVERRIDE_REBOOT_PREREQ ]


OPTIONS:
--help          prints this message
--sanity_check  runs all sanity checks and exits
--downloadonly  downloads packages to be updated in the /var/cache/yum subdirs
--update        updates installed RPM packages
--verify        verify RPMs are up to date for configured repositories
--noyumclean    preserves yum cache (default is to clear all yum cache)
--security_file change the file name which determines security only restriction
--no-reboot     disables the reboot which normally follows a successful update

--no_channel_verification  disables the Satellite channel verify
--OVERRIDE_REBOOT_PREREQ   skip the required 280 day initial reboot check


EXAMPLES:

  o  Preserve yum cache then update RPM packages

     $0 --noyumclean --update

  o  Only download the RPM packages to be updated do not install them

     $0 --downloadonly

  o  Update RPM packages but suppress the reboot as the end (useful for HP-OO)

     $0 --no-reboot --update

USAGE
    exit 0
}

#-------------------------------------------------------------------------------
function    set_global_info_string() {
#-------------------------------------------------------------------------------
# PURPOSE: generate an info string to ensure all messages have a similar format
#-------------------------------------------------------------------------------
# INPUT: N/A
#-------------------------------------------------------------------------------
# OUTPUT: informational string is updated in the global info variable
#-------------------------------------------------------------------------------
# ASSUMPTIONS: N/A
#-------------------------------------------------------------------------------
    info="${0##*/}: $( 'date' +'%Y-%b-%d %H:%M:%S %Z' ): ${HOSTNAME%%.*}"
}

#-------------------------------------------------------------------------------
function    ERROR() {
#-------------------------------------------------------------------------------
# PURPOSE: provide a common error mechanism
#-------------------------------------------------------------------------------
# INPUT:
# o  errno is the exit status (1-255)
# o  message is the error message string
#-------------------------------------------------------------------------------
# OUTPUT: error message is tagged and printed to STDERR
#-------------------------------------------------------------------------------
# ASSUMPTIONS:
# o errno is a whole number between 1 and 255 and maybe 1 or 255 as well
#-------------------------------------------------------------------------------
    local errno=$1
    local message=$2

    set_global_info_string
    echo "ERROR: $info: $message" >&2
    exit ${errno:-'255'}
}

#-------------------------------------------------------------------------------
function    WARN() {
#-------------------------------------------------------------------------------
# PURPOSE: provide a common warning mechanism
#-------------------------------------------------------------------------------
# INPUT:
# o  message is the warning message string
#-------------------------------------------------------------------------------
# OUTPUT: warning message is tagged and printed to STDERR
#-------------------------------------------------------------------------------
# ASSUMPTIONS: N/A
#-------------------------------------------------------------------------------
    local message=$1
    set_global_info_string
    echo "WARN: $info: $message" >&2
}

#-------------------------------------------------------------------------------
function    INFO() {
#-------------------------------------------------------------------------------
# PURPOSE: provide a common informational messaging mechanism
#-------------------------------------------------------------------------------
# INPUT:
# o  message is the informational message string
#-------------------------------------------------------------------------------
# OUTPUT: informational message is tagged and printed to STDERR
#-------------------------------------------------------------------------------
# ASSUMPTIONS: N/A
#-------------------------------------------------------------------------------
    local message=$1
    set_global_info_string
    echo "INFO: $info: $message"
}

#-------------------------------------------------------------------------------
function    define_global_variables {
#-------------------------------------------------------------------------------
# PURPOSE: defines a set of script global environment variables
#-------------------------------------------------------------------------------
# INPUT: NA
#-------------------------------------------------------------------------------
# OUTPUT: iniitalizes a set of script global environment variables
#-------------------------------------------------------------------------------
# ASSUMPTIONS: NA
#-------------------------------------------------------------------------------
    yum_security_only_file='/etc/yum/.yum-security-only-updates'

    # script global variables for command line options
    noyumclean=''
    downloadonly='' # Note: this variable is also used in run_yum_update
    security_file='' # redefines $yum_security_only_file if it exists
    no_reboot=''
    sanity_check=''
    update=''
    verify=''
    NO_CHANNEL_VERIFICATION=''
    OVERRIDE_REBOOT_PREREQ=''
}

#-------------------------------------------------------------------------------
function    process_command_line_options() {
#-------------------------------------------------------------------------------
# PURPOSE: process the command line options provided to the script
#-------------------------------------------------------------------------------
# INPUT: command line options are passed via "$@" from the main script
#-------------------------------------------------------------------------------
# OUTPUT: updates script global variables for valid command line arguments
#-------------------------------------------------------------------------------
# ASSUMPTIONS:
# o  getopt command supports multiple instances of long options using -l <name>
#-------------------------------------------------------------------------------
    local options="-l noyumclean -l downloadonly -l security_file: -l no-reboot
                   -l update -l verify -l no_channel_verification
                   -l sanity_check -l OVERRIDE_REBOOT_PREREQ"

    # note: getopt does NOT work correctly when local scope is applied to OPTS
    OPTS=$( "getopt" -o '' -l help $options -- $@ )
    if [[ $? != 0 ]];then
        ERROR 10 "failed to parse commandline arguments"
    fi

    eval set -- "$OPTS"

    while true; do
        first_arg=${1#--}
        case "$1" in
            --help)
                usage
            ;;
            --noyumclean)
                noyumclean="true"
                shift
            ;;
            --downloadonly)
                downloadonly="$1"
                OVERRIDE_REBOOT_PREREQ='true'
                update="true"
                shift
            ;;
            --security_file)
                yum_security_only_file="$2"
                shift 2
            ;;
            --no-reboot)
                no_reboot="true"
                shift
            ;;
            --sanity_check)
                sanity_check="true"
                shift
            ;;
            --update)
                update="true"
                shift
            ;;
            --verify)
                verify="true"
                OVERRIDE_REBOOT_PREREQ='true'
                shift
            ;;
            --no_channel_verification)
                NO_CHANNEL_VERIFICATION='true'
                shift
            ;;
            --OVERRIDE_REBOOT_PREREQ)
                OVERRIDE_REBOOT_PREREQ='true'
                shift
            ;;
            --)
                first_arg=''
                shift
                break
            ;;
        esac

        if [[ -n $first_arg ]];then
            INFO "command line argument set: ==> $first_arg"
        fi
    done

    if [[ -n "$@" ]];then
        ERROR 20 "unhandled command line arguments found: $@"
    fi
}

#-------------------------------------------------------------------------------
function    run_yum_complete_transaction() {
#-------------------------------------------------------------------------------
# PURPOSE: run the yum-complete-transaction command if yum-utils is installed
#-------------------------------------------------------------------------------
# INPUT: N/A
#-------------------------------------------------------------------------------
# OUTPUT: if present the most recent incomplete yum transaction is completed
#-------------------------------------------------------------------------------
# ASSUMPTIONS:
# o  at most a single incomplete yum transaction exists
#-------------------------------------------------------------------------------
# NOTE: if multiple incomplete transactions exist then yum-complete-transaction
#       should be run to complete each of these failed transactions.  However,
#       the existing command below will only complete the most recent incomplete
#       transaction.
#-------------------------------------------------------------------------------
    if ( "rpm" -q yum-utils | "grep" 'el[67]' > /dev/null );then
        if ! "yum-complete-transaction" --assumeyes;then
            ERROR 40 "failed yum-complete-transaction"
        fi
    fi
}

#-------------------------------------------------------------------------------
function    setup_symlink_workaround_environmental_variables() {
#-------------------------------------------------------------------------------
# PURPOSE: initializes global variables used by symlink workaround functions
#-------------------------------------------------------------------------------
# INPUT: N/A
#-------------------------------------------------------------------------------
# OUTPUT: global variables: POSSIBLE_SYMLINKS_TO_PERSERVE DATE PRESERVED_SUFFIX
#-------------------------------------------------------------------------------
# ASSUMPTIONS:
# o  PRESERVED_SUFFIX is unique enough not to conflict with existing files
#-------------------------------------------------------------------------------
    POSSIBLE_SYMLINKS_TO_PERSERVE="
        /usr/bin/perl
    "
    DATE=$( date +'%Y%m%d%H%M%S' )
    PRESERVED_SUFFIX="-symlink-preserved-$DATE"
}

#-------------------------------------------------------------------------------
function    cat_log_file_to_stdout() {
#-------------------------------------------------------------------------------
# PURPOSE: cat $log_file to standard out
#-------------------------------------------------------------------------------
# INPUT: N/A
#-------------------------------------------------------------------------------
# OUTPUT: $log_file is concatenated to standard out
#-------------------------------------------------------------------------------
# ASSUMPTIONS: N/A
#-------------------------------------------------------------------------------
    exec 1<&3 3<&- # restore stdout from fd #3 and close fd #3
    exec 2<&4 4<&- # restore stderr from fd #4 and close fd #4

    INFO "concatenating contents of the log file: $log_file"
    cat $log_file
}

#-------------------------------------------------------------------------------
function    log_output_to_tmp_directory() {
#-------------------------------------------------------------------------------
# PURPOSE: log standard out and standard error to $log_file
#-------------------------------------------------------------------------------
# INPUT: N/A
#-------------------------------------------------------------------------------
# OUTPUT: all standard out and standard error output is logged to $log_file
#-------------------------------------------------------------------------------
# ASSUMPTIONS: N/A
#-------------------------------------------------------------------------------
    log_file="/tmp/${HOSTNAME%%.*}.$( 'date' +'%Y%m%d%H%M%S' ).log"
    INFO "redirecting all STDERR & STDOUT to the log file: $log_file"

    exec 3<&1          # Saves stdout to file descriptor #3
    exec 4<&2          # Saves stderr to file descriptor #4
    exec > $log_file 2>&1 # redirect stdout and stderr to $log_file

    # set trap to concatenate log_file on exit
    trap cat_log_file_to_stdout 0
}

#-------------------------------------------------------------------------------
function    reboot_server {
#-------------------------------------------------------------------------------
# PURPOSE: gracefully reboot by transitioning to runlevel 6
#-------------------------------------------------------------------------------
# INPUT: N/A
#-------------------------------------------------------------------------------
# OUTPUT: server is rebooted
#-------------------------------------------------------------------------------
# ASSUMPTIONS:
# o  this function is always called in the background using an ampersand "&"
#-------------------------------------------------------------------------------
    INFO "requesting system reboot"
    exec 0>&- # close stdin
    exec 1>&- # close stdout
    exec 2>&- # close stderr
    "sleep" 10
    "nohup" "init" 6
}

#-------------------------------------------------------------------------------
function    reboot_required_if_uptime_is_over_280_days_before_updating {
#-------------------------------------------------------------------------------
# PURPOSE: restrict running on only systems with less than 280 days of uptime
#-------------------------------------------------------------------------------
# INPUT: N/A
#-------------------------------------------------------------------------------
# OUTPUT: exits with error message if uptime is greater than 280 days
#-------------------------------------------------------------------------------
# ASSUMPTIONS:
# o  the first item in /proc/uptime is a number of seconds since its last reboot
#-------------------------------------------------------------------------------
    local day_in_seconds=$(( 24 * 60 * 60 ))
    local secs_for_280_days=$(( 280 * $day_in_seconds ))
    local uptime_in_seconds=$( "cut" -d. -f1 /proc/uptime )
    local uptime_in_days=$(( $uptime_in_seconds / $day_in_seconds ))

    local mask='last reboot was %s days ago which is %sless than 280 days\n'

    if [[ $secs_for_280_days -gt $uptime_in_seconds ]];then
       INFO "$( printf "$mask" "$uptime_in_days" "" )"
    else
       WARN "$( printf "$mask" "$uptime_in_days" "NOT " )"
       ERROR 180 "Please reboot this server then try running this script again"
    fi
}

#-------------------------------------------------------------------------------
function    copy_symlink() {
#-------------------------------------------------------------------------------
# PURPOSE: create a backup for each symbolic link identified to be preserved
#-------------------------------------------------------------------------------
# INPUT:
# o  symlink is a file location for the symbolic link to be copied
# o  copied_link is the path where the symlink will be copied to
#-------------------------------------------------------------------------------
# OUTPUT: copied_link is created as another symbolic link using symlink the src
#-------------------------------------------------------------------------------
# ASSUMPTIONS:
# o  symlink is an existing symbolic link
# o  copied_link does not exist before invoking this function
# o  the process ownership has write access to the copied_link parent directory
#-------------------------------------------------------------------------------
    local symlink=$1
    local copied_link=$2

    if [[ -L $symlink ]];then
        local link_destination=$( "ls" -l $symlink | "awk" '{ print $NF }' )
        if ! "ln" -s $link_destination $copied_link;then
            ERROR 55 "failed to copy symlink $symlink to $copied_link"
        fi
    else
        ERROR 57 "symlink $symlink is NOT a symlink failed to copy $copied_link"
    fi
}

#-------------------------------------------------------------------------------
function    backup_workaround_symbolic_links() {
#-------------------------------------------------------------------------------
# PURPOSE: create a backup for each symbolic link identified to be preserved
#-------------------------------------------------------------------------------
# INPUT: global variables: POSSIBLE_SYMLINKS_TO_PERSERVE PRESERVED_SUFFIX
#-------------------------------------------------------------------------------
# OUTPUT: BACKUP is created for each symbolic link as preparation for restore
#-------------------------------------------------------------------------------
# ASSUMPTIONS:
# o  backup files are used by restore_workaround_symbolic_links
#-------------------------------------------------------------------------------
    for symlink in $POSSIBLE_SYMLINKS_TO_PERSERVE;do
        local BACKUP="$symlink$PRESERVED_SUFFIX"
        if [[ -L $symlink ]];then
            if copy_symlink $symlink $BACKUP;then
                INFO "created a backup of $symlink as $BACKUP"
            else
                ERROR 60 "failed to create a backup of $symlink as $BACKUP"
            fi
        fi
    done
}

#-------------------------------------------------------------------------------
function    determine_relocate_and_restore() {
#-------------------------------------------------------------------------------
# PURPOSE: given symlink and backup determine whether to relocate and/or restore
#-------------------------------------------------------------------------------
# INPUT:
# o  symlink is a file location of the original symlink location
# o   backup is a file location of the original symlink backup location
#-------------------------------------------------------------------------------
# OUTPUT: return values for relocate followed by restore where 0=false & 1=true
#-------------------------------------------------------------------------------
# ASSUMPTIONS: N/A
#-------------------------------------------------------------------------------
    local symlink=$1
    local backup=$2

    local relocate
    local restore

    if [[ ! -e $symlink ]];then
        # if symlink does NOT exist then do NOT relocate just restore
        relocate=0
        restore=1
    elif [[ ! -L $symlink ]];then
        # if symlink exists but is not a symbolic link then relocate and restore
        relocate=1
        restore=1
    elif [[ $( "cmp" $symlink $backup ) -eq 0 ]];then
        # if symlink and backup are identical do NOT do NOT relocate nor restore
        relocate=0
        restore=0
    else
        # otherwise symlink and backup diff and therefore relocate and restore
        relocate=1
        restore=1
    fi

    echo $relocate $restore
}

#-------------------------------------------------------------------------------
function    remove_files_from_previous_failures() {
#-------------------------------------------------------------------------------
# PURPOSE: find and remove files from previous failed runs
#-------------------------------------------------------------------------------
# INPUT:
# o  related_file_pattern is a fqn prefix for finding files of prior failed runs
#-------------------------------------------------------------------------------
# OUTPUT: notification and removal of files from previous runs
#-------------------------------------------------------------------------------
# ASSUMPTIONS: N/A
#-------------------------------------------------------------------------------
    local related_file_pattern=$1
    local old_file

    for old_file in $related_file_pattern*;do
        if [[ -e $old_file ]];then
            if "rm" -f $old_file;then
                INFO "removed temp file from prior run: $old_file"
            else
                WARN "failed to remove temp file from prior run: $old_file"
            fi
        fi
    done
}

#-------------------------------------------------------------------------------
function    restore_relocated_file() {
#-------------------------------------------------------------------------------
# PURPOSE: restore the relocated file in the event that no symlink file exists
#-------------------------------------------------------------------------------
# INPUT:
# o  relocate is a file location of the new symlink relocate location
# o   symlink is a file location of the original symlink location
#-------------------------------------------------------------------------------
# OUTPUT: if relocate file exists it is used to restore the symlink file
#-------------------------------------------------------------------------------
# ASSUMPTIONS: N/A
# o  symlink file does NOT exist prior to calling this function
#-------------------------------------------------------------------------------
    local relocate=$1
    local symlink=$2

    if [[ -e $relocate ]];then
        if "mv" $relocate $symlink;then
            INFO "restored relocated file $relocate to $symlink"
        else
            WARN "failed to restore $relocate to $symlink"
        fi
    fi
}

#-------------------------------------------------------------------------------
function    restore_workaround_symbolic_links() {
#-------------------------------------------------------------------------------
# PURPOSE: restore symbolic links preserved by backup_workaround_symbolic_links
#-------------------------------------------------------------------------------
# INPUT: global variables: POSSIBLE_SYMLINKS_TO_PERSERVE DATE PRESERVED_SUFFIX
#-------------------------------------------------------------------------------
# OUTPUT: backed up symbolic links are restored and existing context is backedup
#-------------------------------------------------------------------------------
# ASSUMPTIONS:
# o  in the case where one symlink fails the script exists immediately without
#    restoring the remaining symlinks as manual intervention will be required
#-------------------------------------------------------------------------------
    for symlink in $POSSIBLE_SYMLINKS_TO_PERSERVE;do
        local BACKUP="$symlink$PRESERVED_SUFFIX"
        RELOCATE="$symlink-$DATE"
        if [[ -L $BACKUP ]];then

            args=( $( determine_relocate_and_restore $symlink $BACKUP ) )
            local relocate=${args[0]}
            local restore=${args[1]}

            if [[ $relocate -eq 1 ]];then
                if "mv" $symlink $RELOCATE;then
                    INFO "relocated $symlink to $RELOCATE"
                else
                    ERROR 70 "failed to relocate $symlink to $RELOCATE"
                fi
            fi

            if [[ $restore -eq 1 ]];then
                # note: the symlink does not exist prior to the restore
                if "mv" $BACKUP $symlink;then
                    INFO "restored $BACKUP to $symlink"
                else
                    restore_relocated_file $RELOCATE $symlink
                    ERROR 80 "failed to restore $BACKUP to $symlink"
                fi
            fi

            if [[ $relocate -eq 0 ]] && [[ $restore -eq 0 ]];then
                INFO "removing $BACKUP as it is identical to $symlink"
                "rm" -f $BACKUP
            fi

            # now that this symlink has been successfully processed cleanup any
            # related files from previous failed runs related to this symlink
            remove_files_from_previous_failures ${BACKUP%$DATE}
        fi
    done
}

#-------------------------------------------------------------------------------
function    get_default_kernel_image() {
#-------------------------------------------------------------------------------
# PURPOSE: get the default kernel image defined in $grub_conf
#-------------------------------------------------------------------------------
# INPUT: N/A
#-------------------------------------------------------------------------------
# OUTPUT: default kernel image location is returned on STDOUT
#-------------------------------------------------------------------------------
# ASSUMPTIONS:
# o  $grub_conf has a default kernel defined where title counts start at 0
#-------------------------------------------------------------------------------
    "perl" -e '
    my $grub_conf="/boot/grub/grub.conf";

    open(GRUB,$grub_conf) or die "ERROR: cannot open $grub_conf: $!";

    my $default=0;
    my $title_count=-1;
    my $release="";

    while (<GRUB>) {
        if ( /^\s*default\s*=\s*(\d+)/ ) {
            $default=$1;
        }
        if ( /^\s*title\s*/ ) {
            $title_count++;
        }
        if ( $default == $title_count and /^\s*kernel\s*(\S+)/ ) {
            $release=$1;
            last
        }
    }
    printf "%s\n",$release;
    '
}

#-------------------------------------------------------------------------------
function    get_grub2_default() {
#-------------------------------------------------------------------------------
# PURPOSE: get the grub2 default tag
#-------------------------------------------------------------------------------
# INPUT: N/A
#-------------------------------------------------------------------------------
# OUTPUT: grub2 default tag is returned on STDOUT
#-------------------------------------------------------------------------------
# ASSUMPTIONS: N/A
#-------------------------------------------------------------------------------
    'awk' -F= '/^GRUB_DEFAULT/ { print $2 }' '/etc/default/grub'
}

#-------------------------------------------------------------------------------
function    get_grub2_kernel_label() {
#-------------------------------------------------------------------------------
# PURPOSE: get the grub2 kernel label
#-------------------------------------------------------------------------------
# INPUT: N/A
#-------------------------------------------------------------------------------
# OUTPUT: grub2 kernel label is returned on STDOUT
#-------------------------------------------------------------------------------
# ASSUMPTIONS: N/A
#-------------------------------------------------------------------------------
    local kernel_tag=$1
    'awk' -F= '/^'"$kernel_tag"'_entry/ { print $2 }' '/boot/grub2/grubenv'
}

#-------------------------------------------------------------------------------
function    get_default_kernel_image_RHEL7() {
#-------------------------------------------------------------------------------
# PURPOSE: get the default kernel image defined for RHEL7
#-------------------------------------------------------------------------------
# INPUT: N/A
#-------------------------------------------------------------------------------
# OUTPUT: default kernel image location is returned on STDOUT
#-------------------------------------------------------------------------------
# ASSUMPTIONS:
# o  The following config files can be used to determine the default kernel
#    /etc/default/grub
#    /boot/grub2/grubenv
#    /boot/grub2/grub.cfg
#-------------------------------------------------------------------------------
    default_kernel_tag=$( get_grub2_default )
    default_kernel_label=$( get_grub2_kernel_label "$default_kernel_tag" )
    "perl" -e '
    my $grub_cfg="/boot/grub2/grub.cfg";
    open(GRUB,$grub_cfg) or die "ERROR: cannot open $grub_cfg: $!";

    my $release="";
    my $menu_found=0;
    my $default_kernel_label = q('"$default_kernel_label"');
    $default_kernel_label =~ s/([\\$\@\%(\)])/\\$1/g;
    my $single_quote = chr(39);
    my $menuentry = "menuentry $single_quote$default_kernel_label$single_quote";
    while (<GRUB>) {
        if ( /^$menuentry/ or $menu_found ) {
            if ( /^\s*menuentry\s*/ and $menu_found ) {
                die "ERROR: unable to determine the menuentry kernel version\n";
            }
            if ( m!^[^#]+\s(/vmlinuz-\S+)! ) {
                $release="$1";
                last;
            }
            $menu_found=1;
        }
    }
    printf "%s\n",$release;
    '
}

#-------------------------------------------------------------------------------
function    get_default_kernel() {
#-------------------------------------------------------------------------------
# PURPOSE: get the default kernel package name using the default image file
#-------------------------------------------------------------------------------
# INPUT:  image is a relative kernel image path
#-------------------------------------------------------------------------------
# OUTPUT: returns the kernel image package on STDOUT
#-------------------------------------------------------------------------------
# ASSUMPTIONS:
# o  the default kernel image function returns a kernel image patch which in
#    owned by some kernel package which defines the version, release and arch
#    attributes
#-------------------------------------------------------------------------------
    local image=""

    if [[ -e "/boot/grub/grub.conf" ]];then
        image=$( get_default_kernel_image )
    else
        image=$( get_default_kernel_image_RHEL7 )
    fi
    "rpm" -qf /boot$image --qf '%{version}-%{release}.%{arch}\n'
}

#-------------------------------------------------------------------------------
function    get_running_kernel() {
#-------------------------------------------------------------------------------
# PURPOSE: get the running kernel release using uname
#-------------------------------------------------------------------------------
# INPUT: N/A
#-------------------------------------------------------------------------------
# OUTPUT: the running kernel release returned via STDOUT
#-------------------------------------------------------------------------------
# ASSUMPTIONS: N/A
#-------------------------------------------------------------------------------
    local UNAME=( $( "uname" -ri ) )

    if [[ ${UNAME[0]} == *".el"[0-9] ]];then
        echo "${UNAME[0]}.${UNAME[1]}"
    else
        echo "${UNAME[0]}"
    fi
}

#-------------------------------------------------------------------------------
function    list_installed_kernels_by_installtime() {
#-------------------------------------------------------------------------------
# PURPOSE: list all installed kernel packages by their installation times
#-------------------------------------------------------------------------------
# INPUT: N/A
#-------------------------------------------------------------------------------
# OUTPUT: returns a list of kernel packages starting with the most recently
#         installed and ending with the oldest kernel package installation time.
#-------------------------------------------------------------------------------
# ASSUMPTIONS: N/A
#-------------------------------------------------------------------------------
    "rpm" -q kernel --qf '%{version}-%{release}.%{arch} %{INSTALLTIME}\n' |
    "sort" -rnk 2,2 |
    "awk" '{ print $1 }'
}

#-------------------------------------------------------------------------------
function    remove_old_kernels() {
#-------------------------------------------------------------------------------
# PURPOSE: remove old kernels by preserving kernels in the following order:
#          1. keep the default kernel (defined in grub.conf)
#          2. keep the running kernel
#          3. keep the most recently installed kernel
#          4. if 1 == 2 then keep the next most recently installed kernel
#-------------------------------------------------------------------------------
# INPUT: N/A
#-------------------------------------------------------------------------------
# OUTPUT: removes old kernel packages if any exist as defined above
#-------------------------------------------------------------------------------
# ASSUMPTIONS: N/A
#-------------------------------------------------------------------------------
    local default="kernel-"$( get_default_kernel )
    local running="kernel-"$( get_running_kernel )
    local keep_kernels=0

    if [[ $default == $running ]];then
        let keep_kernels=2
    else
        let keep_kernels=1
    fi

    for kernel in $( list_installed_kernels_by_installtime );do

        kernel="kernel-$kernel"

        if [[ $kernel == $default ]];then
            INFO "keeping the default $kernel"

        elif [[ $kernel == $running ]];then
            INFO "keeping the running $kernel"

        elif [[ $keep_kernels -ge 1 ]];then
            INFO "keeping the most recently installed $keep_kernels: $kernel"
            let keep_kernels="$keep_kernels - 1"

        else
            INFO "removing $kernel"
            'yum' -y remove $kernel
        fi
    done
}

#-------------------------------------------------------------------------------
function    list_rpms {
#-------------------------------------------------------------------------------
# PURPOSE: generate a list of installed RPMs to standard out
#-------------------------------------------------------------------------------
# INPUT: N/A
#-------------------------------------------------------------------------------
# OUTPUT: list of installed RPMs in sorted order to standard out
#-------------------------------------------------------------------------------
# ASSUMPTIONS: N/A
#-------------------------------------------------------------------------------
    'rpm' -qa --qf '%{name}-%{version}-%{release}.%{arch}\n' | sort 2>&1
}

#-------------------------------------------------------------------------------
function    generate_rpm_list {
#-------------------------------------------------------------------------------
# PURPOSE: generate a list of installed RPMs to standard out with a description
#-------------------------------------------------------------------------------
# INPUT: N/A
#-------------------------------------------------------------------------------
# OUTPUT: list of installed RPMs in sorted order to standard out
#         otherwise exits with an error message detailing the problem
#-------------------------------------------------------------------------------
# ASSUMPTIONS: N/A
#-------------------------------------------------------------------------------
    msg=$1
    INFO "The following is a listing of installed RPMS $msg updating"
    if ! list_rpms;then
        ERROR 100 "failed to generate installed RPM list"
    fi
}

#-------------------------------------------------------------------------------
function    run_yum_clean_all {
#-------------------------------------------------------------------------------
# PURPOSE: remove the yum metadata
#-------------------------------------------------------------------------------
# INPUT: N/A
#-------------------------------------------------------------------------------
# OUTPUT: yum metadata is removed to ensure a clean start when the update is run
#-------------------------------------------------------------------------------
# ASSUMPTIONS:
# o  existing yum configuration is configured correctly
#-------------------------------------------------------------------------------
    INFO "RUNNING: yum clean all"

    if 'yum' clean all;then
        INFO "yum clean all completed successfully"
    else
        ERROR 125 "failed running: yum clean all"
    fi
}

#-------------------------------------------------------------------------------
function    get_yum_exclude_list {
#-------------------------------------------------------------------------------
# PURPOSE: get the yum package exclude arguments for ignoring packages
#-------------------------------------------------------------------------------
# INPUT: N/A
#-------------------------------------------------------------------------------
# OUTPUT: return a list of package exclude argument for yum via STDOUT
#-------------------------------------------------------------------------------
# ASSUMPTIONS: NA
#-------------------------------------------------------------------------------
    local ignored_packages="
        hp-nx_nic-tools
        hpvca.i386
    "
    local package
    local excludes
    for package in $ignored_packages;do
        if [[ -n $excludes ]];then
            excludes="$excludes --exclude $package"
        else
            excludes="--exclude $package"
        fi
    done
    echo "$excludes"
}

#-------------------------------------------------------------------------------
function    yum_check_security_only_update {
#-------------------------------------------------------------------------------
# PURPOSE: verify that yum has access to security only updates or not
#-------------------------------------------------------------------------------
# INPUT: N/A
#-------------------------------------------------------------------------------
# OUTPUT: return   0 if there are no new security updates available
#         otherwise exits with an error message detailing the problem
#-------------------------------------------------------------------------------
# ASSUMPTIONS:
# o  yum configuration is configured correctly including the security plugin
# o  excludes are not supported by yum list-security --security
#-------------------------------------------------------------------------------
    local final=$1
    INFO "RUNNING: yum list-security --security"

    OUTPUT=$( 'yum' list-security --security )
    local RETVAL=$?
    OUTPUT=$( 'echo' "$OUTPUT" | 'awk' '$2 ~ /^security$/' )

    if [[ $RETVAL -ne 0 ]];then
        WARN "failed running: yum list-security --security"
        RETVAL=10

    elif [[ -z $OUTPUT ]];then
        INFO "yum appears to have all available security updates"

    elif [[ -n $final ]];then
        echo "$OUTPUT" | 'awk' '/[a-z]/ {print "WARN: " $0 }'
        WARN "security update required based on yum list-security --security"
        RETVAL=100
    else
        echo "$OUTPUT" | 'awk' '/[a-z]/ {print "INFO: " $0 }'
        INFO "yum has security related updates that have not been applied"
        RETVAL=100
    fi

    return $RETVAL
}

#-------------------------------------------------------------------------------
function    yum_check_update_all {
#-------------------------------------------------------------------------------
# PURPOSE: verify that yum has access to updates or not
#-------------------------------------------------------------------------------
# INPUT: N/A
#-------------------------------------------------------------------------------
# OUTPUT: return   0 if there are no new updates available
#         return 100 if there are new updates available
#         otherwise exits with an error message detailing the problem
#-------------------------------------------------------------------------------
# ASSUMPTIONS:
# o  existing yum configuration is configured correctly
#-------------------------------------------------------------------------------
    local final=$1
    local excludes=$( get_yum_exclude_list )
    INFO "RUNNING: yum check-update $excludes"
    'yum' check-update $excludes
    local RETVAL=$?

    if [[ $RETVAL -eq 0 ]];then
        INFO "yum appears to have all available updates"

    elif [[ $RETVAL -eq 100 ]] && [[ -n $final ]];then
            WARN "update required based on yum check-update $excludes"

    elif [[ $RETVAL -eq 100 ]];then
            INFO "yum update required"

    else
        WARN "failed running: yum check-update $excludes"
    fi

    return $RETVAL
}

#-------------------------------------------------------------------------------
function    yum_check_update {
#-------------------------------------------------------------------------------
# PURPOSE: check to see if any yum updates are available
#-------------------------------------------------------------------------------
# INPUT: N/A
#-------------------------------------------------------------------------------
# OUTPUT: redirect to yum_check_update_all or yum_check_security_only_update
#-------------------------------------------------------------------------------
# ASSUMPTIONS: NA
#-------------------------------------------------------------------------------
    securityonly=""
    if [[ -e $yum_security_only_file ]];then
        securityonly="--security"
        yum_check_security_only_update $*
    else
        yum_check_update_all $*
    fi
}

#-------------------------------------------------------------------------------
function    run_yum_update {
#-------------------------------------------------------------------------------
# PURPOSE: apply any yum updates which are available
#-------------------------------------------------------------------------------
# INPUT: N/A
#-------------------------------------------------------------------------------
# OUTPUT: if available RPMs are updated using the existing yum configuration
#-------------------------------------------------------------------------------
# ASSUMPTIONS:
# o  existing yum configuration is configured correctly
#-------------------------------------------------------------------------------
    yum_check_update
    local RETVAL=$?

    if [[ $RETVAL -eq 0 ]];then
       INFO  "yum update NOT required"
    else
       local excludes=$( get_yum_exclude_list )
       generate_rpm_list 'before' > ${log_file%log}rpms-before
       INFO "RUNNING: yum -y update $securityonly $downloadonly $excludes"
       'yum' -y update $securityonly $downloadonly $excludes
       generate_rpm_list 'after' > ${log_file%log}rpms-after
    fi
}

#-------------------------------------------------------------------------------
function    get_redhat_release {
#-------------------------------------------------------------------------------
# PURPOSE: get the redhat major and minor release numbers
#-------------------------------------------------------------------------------
# INPUT: NA
#-------------------------------------------------------------------------------
# OUTPUT: returns the redhat major and minor release numbers
#-------------------------------------------------------------------------------
# ASSUMPTIONS:
# o  redhat_release is defined as a global variable
#-------------------------------------------------------------------------------
    'sed' -e 's/[.]/ /g;s/[^0-9 ]//g;s/  */ /g;s/^ *//;s/ *$//' $redhat_release
}

#-------------------------------------------------------------------------------
function    update_ostype_with_redhat_os_version {
#-------------------------------------------------------------------------------
# PURPOSE: update OSTYPE global environment variable with the Red Hat OS version
#-------------------------------------------------------------------------------
# INPUT: NA
#-------------------------------------------------------------------------------
# OUTPUT: defines the global variables: SYSTYPE, OSTYPE, redhat_release
#-------------------------------------------------------------------------------
# ASSUMPTIONS:
# o  uname command returns the OS type by default
#-------------------------------------------------------------------------------
    [[ -n $SYSTYPE ]] || SYSTYPE=$( 'uname' )

    if [[ $SYSTYPE == 'Linux' ]];then
        redhat_release=/etc/redhat-release
        if [[ -e $redhat_release ]];then
            if 'grep' '^Red Hat Enterprise' $redhat_release > $IGNORE 2>&1;then
                distro='RHEL'
            else
                distro='RHL'
            fi
            local release=$( get_redhat_release )
            OSTYPE=RHEL${release% [0-9]*}.${release#[0-9] }
        fi
    else
        # initial OSTYPE with SYSTYPE unless already defined
        [[ -n $OSTYPE ]] || OSTYPE=$SYSTYPE
    fi
}

#-------------------------------------------------------------------------------
function    restrict_os_to_RHEL_5_6_or_7 {
#-------------------------------------------------------------------------------
# PURPOSE: only allow this script to run on RHEL5, RHEL6 or RHEL7 servers
#-------------------------------------------------------------------------------
# INPUT: NA
#-------------------------------------------------------------------------------
# OUTPUT: notify user whether this OSTYPE is supported or not
#-------------------------------------------------------------------------------
# ASSUMPTIONS: NA
#-------------------------------------------------------------------------------
    update_ostype_with_redhat_os_version

    case "$OSTYPE" in
        RHEL[765]*)
            INFO "$OSTYPE is supported by this script"
        ;;
        *)
            ERROR 30 "$OSTYPE is NOT supported by this script"
        ;;
    esac
}

#-------------------------------------------------------------------------------
function    get_most_recent_kernel_or_openssl_install_time {
#-------------------------------------------------------------------------------
# PURPOSE: get the most recently kernel or openssl package installation time
#-------------------------------------------------------------------------------
# INPUT: NA
#-------------------------------------------------------------------------------
# OUTPUT: return the most recent package installation time in seconds since 1970
#-------------------------------------------------------------------------------
# ASSUMPTIONS: NA
#-------------------------------------------------------------------------------
    local pkgs="kernel openssl"
    local recent_pkg_info=$( 'rpm' -q $pkgs --last | 'head' -1 )
    local dateNtime=$( echo "$recent_pkg_info" | 'awk' '$NF ~ /^+08$/ { print "SGT" } { $1=""; print }')
    if [[ -n $dateNtime ]];then
        echo "DEBUG: recent_pkg_info: " $recent_pkg_info >&2
        'date' -d "$dateNtime" +'%s'
    else
        echo 0
    fi
}

#-------------------------------------------------------------------------------
function    epoch_to_localtime() {
#-------------------------------------------------------------------------------
# PURPOSE: use perl to convert epoch to localtime
#-------------------------------------------------------------------------------
# INPUT: epoch which is a number of seconds since 1970
#-------------------------------------------------------------------------------
# OUTPUT: returns localtime similar to the date command output
#-------------------------------------------------------------------------------
# ASSUMPTIONS: NA
#-------------------------------------------------------------------------------
    local epoch=${1:-0}
    'perl' -e "print localtime($epoch).qq(\\n)"
}

#-------------------------------------------------------------------------------
function    require_root {
#-------------------------------------------------------------------------------
# PURPOSE: ensure that only user with uid=0(root) access invokes this script
#-------------------------------------------------------------------------------
# INPUT: NA
#-------------------------------------------------------------------------------
# OUTPUT: provides and informational or error message based on the user running
#         this script.  if the user is not root it will exit
#-------------------------------------------------------------------------------
# ASSUMPTIONS:
# o  the id command returns the user identification number (uid) with the -u arg
#-------------------------------------------------------------------------------
    # 1b. report and exit if is NOT run by uid=0(root)
    user_id=$( "id" -u )

    if [[ $user_id == 0 ]];then
        INFO "user identification is uid=$user_id(root) as required"
    else
        ERROR 50 "required uid=0(root) NOT $user_id"
    fi
}

#-------------------------------------------------------------------------------
function    get_dmidecode_first_product_name {
#-------------------------------------------------------------------------------
# PURPOSE: filter dmidecode output to get the first product name
#-------------------------------------------------------------------------------
# INPUT: this function is called passing the output of dmidecode over STDIN
#-------------------------------------------------------------------------------
# OUTPUT: returns the first production name
#-------------------------------------------------------------------------------
# ASSUMPTIONS: NA
#-------------------------------------------------------------------------------
    "grep" 'Product Name:' | "head" -1 | "cut" -d: -f2
}

#-------------------------------------------------------------------------------
function    run_sanity_checks {
#-------------------------------------------------------------------------------
# PURPOSE: organize a list of sanity checks to make easier to call as a group
#-------------------------------------------------------------------------------
# INPUT: NA
#-------------------------------------------------------------------------------
# OUTPUT: runs each of the sanity check functions mentioned below
#-------------------------------------------------------------------------------
# ASSUMPTIONS:
# o  regarding yum_security_only_file
#    - RHEL 7: yum package is installed
#    - RHEL 6: yum and yum-plugin-security packages are installed
#    - RHEL 5: yum and yum-security packages are installed
#    - yum fails if unsupported option(s) are provided
#-------------------------------------------------------------------------------
    restrict_os_to_RHEL_5_6_or_7
    require_root

    if [[ $OVERRIDE_REBOOT_PREREQ == 'true' ]];then
        WARN "skipping the prerequisite 280 day reboot check"
    else
        reboot_required_if_uptime_is_over_280_days_before_updating
    fi
}

#-------------------------------------------------------------------------------
function    requires_a_reboot {
#-------------------------------------------------------------------------------
# PURPOSE: ensure the system has been rebooted since the required reboot time
#-------------------------------------------------------------------------------
# INPUT: NA
#-------------------------------------------------------------------------------
# OUTPUT: provides an informational or error message depending if the system
#         required a reboot or not
#-------------------------------------------------------------------------------
# ASSUMPTIONS: NA
#-------------------------------------------------------------------------------
    local min_reboot_time=$( get_most_recent_kernel_or_openssl_install_time )
    local uptime_in_seconds=$( "sed" 's/[^0-9].*$//' /proc/uptime )
    local current_epoch=$( 'date' +'%s' )
    local last_reboot_time=$(( current_epoch - uptime_in_seconds ))
    local last_reboot="last_reboot($( epoch_to_localtime $last_reboot_time ))"
    local min_reboot="min_reboot($( epoch_to_localtime $min_reboot_time ))"

    if [[ $last_reboot_time -gt $min_reboot_time ]];then
        INFO "reboot NOT required: $last_reboot > $min_reboot"
        # disable the post reboot if reboot is NOT required
        no_reboot="true"
    else
        if [[ -n $verify ]];then
            ERROR 250 "reboot required: $last_reboot < $min_reboot"
        else
            # only warn when performing an update so reboot has a chance to run
            WARN "reboot required: $last_reboot < $min_reboot"
        fi
    fi
}

#-------------------------------------------------------------------------------
function    run_package_verification {
#-------------------------------------------------------------------------------
# PURPOSE: verify RHEL 5, 6 or 7 package updater PM as follows:
#
# 1.  Red Hat Satellite channels are configured where applicable
#     a.  all RHEL contain the following channels (note: DEV, TEST & PROD differ)
#         For example:
#         rhel-6-server-rh-common-rpms
#         rhel-6-server-rhn-tools-rpms
#         rhel-6-server-rpms
#         rhel-6-server-satellite-tools-6.2-rpms
#
# 2.  all installed packages are up to date with the configured repositories
#-------------------------------------------------------------------------------
# ASSUMPTIONS: NA
#-------------------------------------------------------------------------------

    yum_check_update 'final' || ERROR 200 "failed attempting to run: yum check update"
    requires_a_reboot
}

#-------------------------------------------------------------------------------
function    main() {
#-------------------------------------------------------------------------------
# PURPOSE: this is the starting point in this script
#-------------------------------------------------------------------------------
# INPUT: "$@" command line values passed to this script itself
#-------------------------------------------------------------------------------
# ASSUMPTIONS: NA
#-------------------------------------------------------------------------------
    define_global_variables
    process_command_line_options "$@"
    run_sanity_checks

    # exit after the sanity check if enabled
    if [[ -n $sanity_check ]];then
        INFO "successfully tested all sanity checks"
        exit 0
    fi

    log_output_to_tmp_directory

    if [[ -n $verify ]];then
        run_package_verification

    elif [[ -n $update ]];then
        [[ -n $noyumclean ]] || run_yum_clean_all
        setup_symlink_workaround_environmental_variables
        backup_workaround_symbolic_links
        run_yum_complete_transaction
        run_yum_update
        remove_old_kernels
        restore_workaround_symbolic_links

        if [[ -z $downloadonly ]];then
            run_package_verification

            [[ -n $no_reboot ]] || reboot_server &
        fi
    else
        ERROR 25 "missing command line argument(s)"
    fi
}

main "$@"
