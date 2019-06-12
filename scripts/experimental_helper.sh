# Read the value of a key in a ynh manifest file
#
# usage: ynh_read_manifest manifest key
# | arg: manifest - Path of the manifest to read
# | arg: key - Name of the key to find
ynh_read_manifest () {
	manifest="$1"
	key="$2"
	python3 -c "import sys, json;print(json.load(open('$manifest', encoding='utf-8'))['$key'])"
}

# Read the upstream version from the manifest 
# this include the number before ~ynh
#
# usage: ynh_app_upstream_version
ynh_app_upstream_version () {
    manifest_path="../manifest.json"
    if [ ! -e "$manifest_path" ]; then
        manifest_path="../settings/manifest.json"	# Into the restore script, the manifest is not at the same place
    fi
    version_key=$(ynh_read_manifest "$manifest_path" "version")
    echo "${version_key/~ynh*/}"
}

# Read package version from the manifest 
# this include the number after ~ynh
#
# usage: ynh_app_package_version
ynh_app_package_version () {
    manifest_path="../manifest.json"
    if [ ! -e "$manifest_path" ]; then
        manifest_path="../settings/manifest.json"	# Into the restore script, the manifest is not at the same place
    fi
    version_key=$(ynh_read_manifest "$manifest_path" "version")
    echo "${version_key/*~ynh/}"
}

# Start or restart a service and follow its booting
#
# usage: ynh_check_starting "Line to match" [Log file] [Timeout] [Service name]
#
# | arg: Line to match - The line to find in the log to attest the service have finished to boot.
# | arg: Log file - The log file to watch
# | arg: Service name
# /var/log/$app/$app.log will be used if no other log is defined.
# | arg: Timeout - The maximum time to wait before ending the watching. Defaut 300 seconds.
ynh_check_starting () {
	local line_to_match="$1"
	local service_name="${4:-$app}"
	local app_log="${2:-/var/log/$service_name/$service_name.log}"
	local timeout=${3:-300}

	ynh_clean_check_starting () {
		# Stop the execution of tail.
		kill -s 15 $pid_tail 2>&1
		ynh_secure_remove "$templog" 2>&1
	}

	echo "Starting of $service_name" >&2
	systemctl restart $service_name
	local templog="$(mktemp)"
	# Following the starting of the app in its log
	tail -F -n1 "$app_log" > "$templog" &
	# Get the PID of the tail command
	local pid_tail=$!

	local i=0
	for i in `seq 1 $timeout`
	do
		# Read the log until the sentence is found, that means the app finished to start. Or run until the timeout
		if grep --quiet "$line_to_match" "$templog"
		then
			echo "The service $service_name has correctly started." >&2
			break
		fi
		echo -n "." >&2
		sleep 1
	done
	if [ $i -eq $timeout ]
	then
		echo "The service $service_name didn't fully started before the timeout." >&2
	fi

	echo ""
	ynh_clean_check_starting
}

# Send an email to inform the administrator
#
# usage: ynh_send_readme_to_admin app_message [recipients]
# | arg: app_message - The message to send to the administrator.
# | arg: recipients - The recipients of this email. Use spaces to separate multiples recipients. - default: root
#	example: "root admin@domain"
#	If you give the name of a YunoHost user, ynh_send_readme_to_admin will find its email adress for you
#	example: "root admin@domain user1 user2"
ynh_send_readme_to_admin() {
	local app_message="${1:-...No specific information...}"
	local recipients="${2:-root}"

	# Retrieve the email of users
	find_mails () {
		local list_mails="$1"
		local mail
		local recipients=" "
		# Read each mail in argument
		for mail in $list_mails
		do
			# Keep root or a real email address as it is
			if [ "$mail" = "root" ] || echo "$mail" | grep --quiet "@"
			then
				recipients="$recipients $mail"
			else
				# But replace an user name without a domain after by its email
				if mail=$(ynh_user_get_info "$mail" "mail" 2> /dev/null)
				then
					recipients="$recipients $mail"
				fi
			fi
		done
		echo "$recipients"
	}
	recipients=$(find_mails "$recipients")

	local mail_subject="☁️🆈🅽🅷☁️: \`$app\` was just installed!"

	local mail_message="This is an automated message from your beloved YunoHost server.

Specific information for the application $app.

$app_message

---
Automatic diagnosis data from YunoHost

$(yunohost tools diagnosis | grep -B 100 "services:" | sed '/services:/d')"

	# Define binary to use for mail command
	if [ -e /usr/bin/bsd-mailx ]
	then
		local mail_bin=/usr/bin/bsd-mailx
	else
		local mail_bin=/usr/bin/mail.mailutils
	fi

	# Send the email to the recipients
	echo "$mail_message" | $mail_bin -a "Content-Type: text/plain; charset=UTF-8" -s "$mail_subject" "$recipients"
}

# Internal helper design to allow helpers to use getopts to manage their arguments
#
# [internal]
#
# example: function my_helper()
# {
#     declare -Ar args_array=( [a]=arg1= [b]=arg2= [c]=arg3 )
#     local arg1
#     local arg2
#     local arg3
#     ynh_handle_getopts_args "$@"
#
#     [...]
# }
# my_helper --arg1 "val1" -b val2 -c
#
# usage: ynh_handle_getopts_args "$@"
# | arg: $@    - Simply "$@" to tranfert all the positionnal arguments to the function
#
# This helper need an array, named "args_array" with all the arguments used by the helper
# 	that want to use ynh_handle_getopts_args
# Be carreful, this array has to be an associative array, as the following example:
# declare -Ar args_array=( [a]=arg1 [b]=arg2= [c]=arg3 )
# Let's explain this array:
# a, b and c are short options, -a, -b and -c
# arg1, arg2 and arg3 are the long options associated to the previous short ones. --arg1, --arg2 and --arg3
# For each option, a short and long version has to be defined.
# Let's see something more significant
# declare -Ar args_array=( [u]=user [f]=finalpath= [d]=database )
#
# NB: Because we're using 'declare' without -g, the array will be declared as a local variable.
#
# Please keep in mind that the long option will be used as a variable to store the values for this option.
# For the previous example, that means that $finalpath will be fill with the value given as argument for this option.
#
# Also, in the previous example, finalpath has a '=' at the end. That means this option need a value.
# So, the helper has to be call with --finalpath /final/path, --finalpath=/final/path or -f /final/path, the variable $finalpath will get the value /final/path
# If there's many values for an option, -f /final /path, the value will be separated by a ';' $finalpath=/final;/path
# For an option without value, like --user in the example, the helper can be called only with --user or -u. $user will then get the value 1.
#
# To keep a retrocompatibility, a package can still call a helper, using getopts, with positional arguments.
# The "legacy mode" will manage the positional arguments and fill the variable in the same order than they are given in $args_array.
# e.g. for `my_helper "val1" val2`, arg1 will be filled with val1, and arg2 with val2.
ynh_handle_getopts_args () {
	# Manage arguments only if there's some provided
	set +x
	if [ $# -ne 0 ]
	then
		# Store arguments in an array to keep each argument separated
		local arguments=("$@")

		# For each option in the array, reduce to short options for getopts (e.g. for [u]=user, --user will be -u)
		# And built parameters string for getopts
		# ${!args_array[@]} is the list of all option_flags in the array (An option_flag is 'u' in [u]=user, user is a value)
		local getopts_parameters=""
		local option_flag=""
		for option_flag in "${!args_array[@]}"
		do
			# Concatenate each option_flags of the array to build the string of arguments for getopts
			# Will looks like 'abcd' for -a -b -c -d
			# If the value of an option_flag finish by =, it's an option with additionnal values. (e.g. --user bob or -u bob)
			# Check the last character of the value associate to the option_flag
			if [ "${args_array[$option_flag]: -1}" = "=" ]
			then
				# For an option with additionnal values, add a ':' after the letter for getopts.
				getopts_parameters="${getopts_parameters}${option_flag}:"
			else
				getopts_parameters="${getopts_parameters}${option_flag}"
			fi
			# Check each argument given to the function
			local arg=""
			# ${#arguments[@]} is the size of the array
			for arg in `seq 0 $(( ${#arguments[@]} - 1 ))`
			do
				# And replace long option (value of the option_flag) by the short option, the option_flag itself
				# (e.g. for [u]=user, --user will be -u)
				# Replace long option with =
				arguments[arg]="${arguments[arg]//--${args_array[$option_flag]}/-${option_flag} }"
				# And long option without =
				arguments[arg]="${arguments[arg]//--${args_array[$option_flag]%=}/-${option_flag}}"
			done
		done

		# Read and parse all the arguments
		# Use a function here, to use standart arguments $@ and be able to use shift.
		parse_arg () {
			# Read all arguments, until no arguments are left
			while [ $# -ne 0 ]
			do
				# Initialize the index of getopts
				OPTIND=1
				# Parse with getopts only if the argument begin by -, that means the argument is an option
				# getopts will fill $parameter with the letter of the option it has read.
				local parameter=""
				getopts ":$getopts_parameters" parameter || true

				if [ "$parameter" = "?" ]
				then
					ynh_die --message="Invalid argument: -${OPTARG:-}"
				elif [ "$parameter" = ":" ]
				then
					ynh_die --message="-$OPTARG parameter requires an argument."
				else
					local shift_value=1
					# Use the long option, corresponding to the short option read by getopts, as a variable
					# (e.g. for [u]=user, 'user' will be used as a variable)
					# Also, remove '=' at the end of the long option
					# The variable name will be stored in 'option_var'
					local option_var="${args_array[$parameter]%=}"
					# If this option doesn't take values
					# if there's a '=' at the end of the long option name, this option takes values
					if [ "${args_array[$parameter]: -1}" != "=" ]
					then
						# 'eval ${option_var}' will use the content of 'option_var'
						eval ${option_var}=1
					else
						# Read all other arguments to find multiple value for this option.
						# Load args in a array
						local all_args=("$@")

						# If the first argument is longer than 2 characters,
						# There's a value attached to the option, in the same array cell
						if [ ${#all_args[0]} -gt 2 ]; then
							# Remove the option and the space, so keep only the value itself.
							all_args[0]="${all_args[0]#-${parameter} }"
							# Reduce the value of shift, because the option has been removed manually
							shift_value=$(( shift_value - 1 ))
						fi

						# Declare the content of option_var as a variable.
						eval ${option_var}=""
						# Then read the array value per value
						local i
						for i in `seq 0 $(( ${#all_args[@]} - 1 ))`
						do
							# If this argument is an option, end here.
							if [ "${all_args[$i]:0:1}" == "-" ]
							then
								# Ignore the first value of the array, which is the option itself
								if [ "$i" -ne 0 ]; then
									break
								fi
							else
								# Else, add this value to this option
								# Each value will be separated by ';'
								if [ -n "${!option_var}" ]
								then
									# If there's already another value for this option, add a ; before adding the new value
									eval ${option_var}+="\;"
								fi
								# Escape double quote to prevent any interpretation during the eval
								all_args[$i]="${all_args[$i]//\"/\\\"}"

								eval ${option_var}+=\"${all_args[$i]}\"
								shift_value=$(( shift_value + 1 ))
							fi
						done
					fi
				fi

				# Shift the parameter and its argument(s)
				shift $shift_value
			done
		}

		# LEGACY MODE
		# Check if there's getopts arguments
		if [ "${arguments[0]:0:1}" != "-" ]
		then
			# If not, enter in legacy mode and manage the arguments as positionnal ones..
			# Dot not echo, to prevent to go through a helper output. But print only in the log.
			set -x; echo "! Helper used in legacy mode !" > /dev/null; set +x
			local i
			for i in `seq 0 $(( ${#arguments[@]} -1 ))`
			do
				# Try to use legacy_args as a list of option_flag of the array args_array
				# Otherwise, fallback to getopts_parameters to get the option_flag. But an associative arrays isn't always sorted in the correct order...
				# Remove all ':' in getopts_parameters
				getopts_parameters=${legacy_args:-${getopts_parameters//:}}
				# Get the option_flag from getopts_parameters, by using the option_flag according to the position of the argument.
				option_flag=${getopts_parameters:$i:1}
				if [ -z "$option_flag" ]; then
						ynh_print_warn --message="Too many arguments ! \"${arguments[$i]}\" will be ignored."
						continue
				fi
				# Use the long option, corresponding to the option_flag, as a variable
				# (e.g. for [u]=user, 'user' will be used as a variable)
				# Also, remove '=' at the end of the long option
				# The variable name will be stored in 'option_var'
				local option_var="${args_array[$option_flag]%=}"

				# Escape double quote to prevent any interpretation during the eval
				arguments[$i]="${arguments[$i]//\"/\\\"}"

				# Store each value given as argument in the corresponding variable
				# The values will be stored in the same order than $args_array
				eval ${option_var}+=\"${arguments[$i]}\"
			done
			unset legacy_args
		else
			# END LEGACY MODE
			# Call parse_arg and pass the modified list of args as an array of arguments.
			parse_arg "${arguments[@]}"
		fi
	fi
	set -x
}

# Create a dedicated fail2ban config (jail and filter conf files)
#
# usage 1: ynh_add_fail2ban_config --logpath=log_file --failregex=filter [--max_retry=max_retry] [--ports=ports]
# | arg: -l, --logpath=   - Log file to be checked by fail2ban
# | arg: -r, --failregex= - Failregex to be looked for by fail2ban
# | arg: -m, --max_retry= - Maximum number of retries allowed before banning IP address - default: 3
# | arg: -p, --ports=     - Ports blocked for a banned IP address - default: http,https
#
# -----------------------------------------------------------------------------
#
# usage 2: ynh_add_fail2ban_config --use_template [--others_var="list of others variables to replace"]
# | arg: -t, --use_template - Use this helper in template mode
# | arg: -v, --others_var=  - List of others variables to replace separeted by a space
# |                           for example : 'var_1 var_2 ...'
#
# This will use a template in ../conf/f2b_jail.conf and ../conf/f2b_filter.conf
#   __APP__      by  $app
#
#  You can dynamically replace others variables by example :
#   __VAR_1__    by $var_1
#   __VAR_2__    by $var_2
#
# Generally your template will look like that by example (for synapse):
#
# f2b_jail.conf:
#     [__APP__]
#     enabled = true
#     port = http,https
#     filter = __APP__
#     logpath = /var/log/__APP__/logfile.log
#     maxretry = 3
#
# f2b_filter.conf:
#     [INCLUDES]
#     before = common.conf
#     [Definition]
#
#     # Part of regex definition (just used to make more easy to make the global regex)
#     __synapse_start_line = .? \- synapse\..+ \-
#
#    # Regex definition.
#    failregex = ^%(__synapse_start_line)s INFO \- POST\-(\d+)\- <HOST> \- \d+ \- Received request\: POST /_matrix/client/r0/login\??<SKIPLINES>%(__synapse_start_line)s INFO \- POST\-\1\- Got login request with identifier: \{u'type': u'm.id.user', u'user'\: u'(.+?)'\}, medium\: None, address: None, user\: u'\5'<SKIPLINES>%(__synapse_start_line)s WARNING \- \- (Attempted to login as @\5\:.+ but they do not exist|Failed password login for user @\5\:.+)$
#
#     ignoreregex =
#
# -----------------------------------------------------------------------------
#
# Note about the "failregex" option:
#          regex to match the password failure messages in the logfile. The
#          host must be matched by a group named "host". The tag "<HOST>" can
#          be used for standard IP/hostname matching and is only an alias for
#          (?:::f{4,6}:)?(?P<host>[\w\-.^_]+)
#
#          You can find some more explainations about how to make a regex here :
#          https://www.fail2ban.org/wiki/index.php/MANUAL_0_8#Filters
#
# Note that the logfile need to exist before to call this helper !!
#
# To validate your regex you can test with this command:
# fail2ban-regex /var/log/YOUR_LOG_FILE_PATH /etc/fail2ban/filter.d/YOUR_APP.conf
#
ynh_add_fail2ban_config () {
  # Declare an array to define the options of this helper.
  local legacy_args=lrmptv
  declare -Ar args_array=( [l]=logpath= [r]=failregex= [m]=max_retry= [p]=ports= [t]=use_template [v]=others_var=)
  local logpath
  local failregex
  local max_retry
  local ports
  local others_var
  local use_template
  # Manage arguments with getopts
  ynh_handle_getopts_args "$@"
  use_template="${use_template:-0}"
  max_retry=${max_retry:-3}
  ports=${ports:-http,https}

  finalfail2banjailconf="/etc/fail2ban/jail.d/$app.conf"
  finalfail2banfilterconf="/etc/fail2ban/filter.d/$app.conf"
  ynh_backup_if_checksum_is_different "$finalfail2banjailconf"
  ynh_backup_if_checksum_is_different "$finalfail2banfilterconf"

  if [ $use_template -eq 1 ]
  then
    # Usage 2, templates
    cp ../conf/f2b_jail.conf $finalfail2banjailconf
    cp ../conf/f2b_filter.conf $finalfail2banfilterconf

    if [ -n "${app:-}" ]
    then
      ynh_replace_string "__APP__" "$app" "$finalfail2banjailconf"
      ynh_replace_string "__APP__" "$app" "$finalfail2banfilterconf"
    fi

    # Replace all other variable given as arguments
    for var_to_replace in ${others_var:-}; do
      # ${var_to_replace^^} make the content of the variable on upper-cases
      # ${!var_to_replace} get the content of the variable named $var_to_replace
      ynh_replace_string --match_string="__${var_to_replace^^}__" --replace_string="${!var_to_replace}" --target_file="$finalfail2banjailconf"
      ynh_replace_string --match_string="__${var_to_replace^^}__" --replace_string="${!var_to_replace}" --target_file="$finalfail2banfilterconf"
    done

  else
    # Usage 1, no template. Build a config file from scratch.
    test -n "$logpath" || ynh_die "ynh_add_fail2ban_config expects a logfile path as first argument and received nothing."
    test -n "$failregex" || ynh_die "ynh_add_fail2ban_config expects a failure regex as second argument and received nothing."

    tee $finalfail2banjailconf <<EOF
[$app]
enabled = true
port = $ports
filter = $app
logpath = $logpath
maxretry = $max_retry
EOF

    tee $finalfail2banfilterconf <<EOF
[INCLUDES]
before = common.conf
[Definition]
failregex = $failregex
ignoreregex =
EOF
  fi

  # Common to usage 1 and 2.
  ynh_store_file_checksum "$finalfail2banjailconf"
  ynh_store_file_checksum "$finalfail2banfilterconf"

  systemctl try-reload-or-restart fail2ban

  local fail2ban_error="$(journalctl -u fail2ban | tail -n50 | grep "WARNING.*$app.*")"
  if [[ -n "$fail2ban_error" ]]; then
    ynh_print_err --message="Fail2ban failed to load the jail for $app"
    ynh_print_warn --message="${fail2ban_error#*WARNING}"
  fi
}

# Remove the dedicated fail2ban config (jail and filter conf files)
#
# usage: ynh_remove_fail2ban_config
ynh_remove_fail2ban_config () {
  ynh_secure_remove "/etc/fail2ban/jail.d/$app.conf"
  ynh_secure_remove "/etc/fail2ban/filter.d/$app.conf"
  systemctl try-reload-or-restart fail2ban
}
