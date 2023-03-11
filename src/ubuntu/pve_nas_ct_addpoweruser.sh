#!/usr/bin/env bash
# ----------------------------------------------------------------------------------
# Filename:     pve_nas_ct_addpoweruser.sh
# Description:  Create a new PVE NAS Power User
# ----------------------------------------------------------------------------------

#---- Bash command to run script ---------------------------------------------------

# Command to run script
# bash -c "$(wget -qLO - https://raw.githubusercontent.com/picasso566/pve-nas/main/src/ubuntu/pve_nas_ct_addpoweruser.sh)"

#---- Source -----------------------------------------------------------------------

DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
COMMON_PVE_SRC_DIR="$DIR/../../common/pve/src"

#---- Dependencies -----------------------------------------------------------------

# Run Bash Header
source $COMMON_PVE_SRC_DIR/pvesource_bash_defaults.sh

# Install libcrack2
if [[ ! $(dpkg -s libcrack2) ]]
then
  apt-get install -y libcrack2 > /dev/null
fi

# Check user is root
if [ ! "$(id -u)" = 0 ]
then
  warn "This script needs to run under 'root'. Exiting in 2 seconds.\nTry again..."
  sleep 2
  exit 0
fi

# Check PVE host SMTP status
check_smtp_status
if [ "$SMTP_STATUS" = 0 ]
then
  display_msg='\nBefore proceeding with this installer we RECOMMEND you first configure all PVE hosts to support SMTP email services. A working SMTP server emails the NAS System Administrator all new User login credentials, SSH keys, application specific login credentials and written guidelines. A PVE host SMTP server makes NAS administration much easier. Also be alerted about unwarranted login attempts and other system critical alerts. PVE Host SMTP Server installer is available in our PVE Host Toolbox located at GitHub:\n\n    --  https://github.com/picasso566/pve-host\n'
fi

#---- Static Variables -------------------------------------------------------------

# List of new users
NEW_USERS=usersfile
# Homes folder
HOSTNAME=$(hostname)
HOME_BASE="/srv/$HOSTNAME/homes"

#---- Other Variables --------------------------------------------------------------

# Easy Script Section Header Body Text
SECTION_HEAD='PVE NAS'

#---- Other Files ------------------------------------------------------------------
#---- Body -------------------------------------------------------------------------

#---- Create New Power User Accounts
section "Create a New Power User Account"

msg_box "#### PLEASE READ CAREFULLY - CREATING POWER USER ACCOUNTS ####
$(if [ "$SMTP_STATUS" = 0 ]; then echo -e ${display_msg}; fi)
Power Users are trusted persons with privileged access to data and application resources hosted on your PVE NAS. Power Users are NOT standard users! Standard users are added at a later stage. Each new Power Users security permissions are controlled by Linux groups. Group security permission levels are as follows:

  --  GROUP NAME    -- PERMISSIONS
  --  'medialab'    -- Everything to do with media (i.e movies, series & music)
  --  'homelab'     -- Everything to do with a smart home including 'medialab'
  --  'privatelab'  -- Private storage including 'medialab' & 'homelab' rights
  
A Personal Home Folder will be created for each new user. The folder name is the new users name. You can access Personal Home Folders and other shares via CIFS/Samba and NFS.

Remember your PVE NAS is also pre-configured with user names specifically tasked for running hosted applications (i.e Proxmox LXC,CT,VM - Sonarr, Radarr, Lidarr). These application users names are as follows:

  --  GROUP NAME    -- USER NAME
  --  'medialab'    -- /srv/CT_HOSTNAME/homes/'media'
  --  'homelab'     -- /srv/CT_HOSTNAME/homes/'home'
  --  'privatelab'  -- /srv/CT_HOSTNAME/homes/'private'"
echo
OPTIONS_VALUES_INPUT=( "TYPE01" "TYPE00" )
OPTIONS_LABELS_INPUT=( "Power User Account - add a new user to the system" \
"None. Exit this User account installer" )
makeselect_input2
singleselect SELECTED "$OPTIONS_STRING"


  #---- Create New Power User Accounts
if [ "$RESULTS" = TYPE01 ]
then
  section "Create a Power User Account"

  # Create new user list
  new_user_LIST=()

  while true
  do
    #---- Create a new username
    while true
    do
      input_username_val
      if [ "$(egrep "^${USERNAME}" /etc/passwd > /dev/null; echo $?)" = 0 ]
      then
        warn "The user '$USERNAME' already exists."
        while true
        do
          read -p "Do you want to try another user name [y/n]? " -n 1 -r YN
          echo
          case $YN in
            [Yy]*)
              info "You have chosen to try another user name.\nTry again..."
              echo
              break 1
              ;;
            [Nn]*)
              echo
              break 3
              ;;
            *)
              warn "Error! Entry must be 'y' or 'n'. Try again..."
              echo
              ;;
          esac
        done
      else
        break
      fi
    done
    echo

    msg "Choose your new user's group member account..."
    OPTIONS_VALUES_INPUT=( "GRP01" "GRP02" "GRP03" )
    OPTIONS_LABELS_INPUT=( "Medialab - Everything to do with media (i.e movies, series and music)" \
    "Homelab - Everything to do with a smart home including medialab" \
    "Privatelab - Private storage including medialab & homelab rights" )
    makeselect_input2
    singleselect SELECTED "$OPTIONS_STRING"

    if [ "$RESULTS" = GRP01 ]
    then
      USERGRP='medialab'
    elif [ "$RESULTS" = GRP02 ]
    then
      USERGRP='homelab -G medialab'
    elif [ "$RESULTS" = GRP03 ]
    then
      USERGRP='privatelab -G medialab,homelab'
    fi

    # Create User password
    input_userpwd_val
    echo

    # Add Username, password, and group to list
    new_user_LIST+=( "$USERNAME $USER_PWD $USERGRP" )

    # List new user details
    msg "Your new user details are as follows:\n"
    printf '%s\n' "${new_user_LIST[@]}" | sed '1 i\USERNAME PASSWORD GROUP' | column -t | indent2
    echo
    # Option to create another user account
    msg "Do you want to create another new jailed user account..."
    OPTIONS_VALUES_INPUT=( "NO" "YES" )
    OPTIONS_LABELS_INPUT=( "No - I do not want to create another user account" \
    "Yes - I want to create another user account" )
    makeselect_input2
    singleselect SELECTED "$OPTIONS_STRING"
    if [ "$RESULTS" = YES ]
    then
      echo
      # break
    elif [ "$RESULTS" = NO ]
    then
      break 2
    fi
  done

  if [ ! "${#new_user_LIST[@]}" = 0 ]
  then
    # Add user to the system
    while read USER PASSWORD GROUP USERMOD
    do
      pass=$(perl -e 'print crypt($ARGV[0], 'password')' $PASSWORD)
      # User home folder pre-existing
      if [ -d "$HOME_BASE/$USER" ]
      then
        # Chattr set user desktop folder attributes to -a
        while read dir
        do
          chattr -i $HOME_BASE/$USER/$dir/.foo_protect
        done < <( ls $HOME_BASE/$USER )
        msg "Creating new user ${USER}..."
        useradd -g $GROUP -p $pass $USERMOD -m -d $HOME_BASE/$USER -s /bin/bash $USER
        msg "Creating default home folders (xdg-user-dirs-update)..."
        sudo -iu $USER xdg-user-dirs-update
        msg "Creating SSH folder and authorised keys file for user ${USER}..."
        mkdir -p $HOME_BASE/$USER/.ssh
        touch $HOME_BASE/$USER/.ssh/authorized_keys
        chmod -R 0700 $HOME_BASE/$USER
        chown -R $USER:$GROUP $HOME_BASE/$USER
        ssh-keygen -o -q -t ed25519 -a 100 -f $HOME_BASE/$USER/.ssh/id_${USER,,}_ed25519 -N ""
        cat $HOME_BASE/$USER/.ssh/id_${USER,,}_ed25519.pub >> $HOME_BASE/$USER/.ssh/authorized_keys
        # Create ppk key for Putty or Filezilla or ProFTPd
        msg "Creating a private PPK key..."
        puttygen $HOME_BASE/$USER/.ssh/id_${USER,,}_ed25519 -o $HOME_BASE/$USER/.ssh/id_${USER,,}_ed25519.ppk
        msg "Creating a public ProFTPd RFC4716 format compliant key..."
        mkdir -p /etc/proftpd/authorized_keys
        touch /etc/proftpd/authorized_keys/${USER}
        ssh-keygen -e -f $HOME_BASE/$USER/.ssh/id_${USER,,}_ed25519.pub >> $HOME_BASE/$USER/.ssh/authorized_keys
        ssh-keygen -e -f $HOME_BASE/$USER/.ssh/id_${USER,,}_ed25519.pub >> /etc/proftpd/authorized_keys/${USER}
        msg "Backing up ${USER} latest SSH keys..."
        BACKUP_DATE=$(date +%Y%m%d-%T)
        mkdir -p /srv/$HOSTNAME/sshkey/${HOSTNAME}_users/${USER,,}_${BACKUP_DATE}
        chown -R root:privatelab /srv/$HOSTNAME/sshkey/${HOSTNAME}_users/${USER,,}_${BACKUP_DATE}
        chmod 0750 /srv/$HOSTNAME/sshkey/${HOSTNAME}_users/${USER,,}_${BACKUP_DATE}
        cp $HOME_BASE/$USER/.ssh/id_${USER,,}_ed25519* /srv/$HOSTNAME/sshkey/${HOSTNAME}_users/${USER,,}_${BACKUP_DATE}/
        msg "Creating $USER smb account..."
        (echo ${PASSWORD}; echo ${PASSWORD} ) | smbpasswd -s -a $USER
        info "User $USER has been added to the system. Existing home folder found.\nUsing existing home folder."
        echo
      elif [ ! -d "$HOME_BASE/$USER" ]; then # Create new user home folder
        msg "Creating new user $USER..."
        useradd -g $GROUP -p $pass $USERMOD -m -d $HOME_BASE/$USER -s /bin/bash $USER
        msg "Creating default home folders (xdg-user-dirs-update)..."
        sudo -iu $USER xdg-user-dirs-update --force
        msg "Creating SSH folder and authorised keys file for user $USER..."
        mkdir -p $HOME_BASE/$USER/.ssh
        touch $HOME_BASE/$USER/.ssh/authorized_keys
        chmod -R 0700 $HOME_BASE/$USER
        chown -R $USER:$GROUP $HOME_BASE/$USER
        ssh-keygen -o -q -t ed25519 -a 100 -f $HOME_BASE/$USER/.ssh/id_${USER,,}_ed25519 -N ""
        cat $HOME_BASE/$USER/.ssh/id_${USER,,}_ed25519.pub >> $HOME_BASE/$USER/.ssh/authorized_keys
        # Create ppk key for Putty or Filezilla or ProFTPd
        msg "Creating a private PPK key..."
        puttygen $HOME_BASE/$USER/.ssh/id_${USER,,}_ed25519 -o $HOME_BASE/$USER/.ssh/id_${USER,,}_ed25519.ppk
        msg "Creating a public ProFTPd RFC4716 format compliant key..."
        mkdir -p /etc/proftpd/authorized_keys
        touch /etc/proftpd/authorized_keys/$USER
        ssh-keygen -e -f $HOME_BASE/$USER/.ssh/id_${USER,,}_ed25519.pub >> $HOME_BASE/$USER/.ssh/authorized_keys
        ssh-keygen -e -f $HOME_BASE/$USER/.ssh/id_${USER,,}_ed25519.pub >> /etc/proftpd/authorized_keys/$USER
        msg "Backing up ${USER} latest SSH keys..."
        BACKUP_DATE=$(date +%Y%m%d-%T)
        mkdir -p /srv/$HOSTNAME/sshkey/${HOSTNAME}_users/${USER,,}_${BACKUP_DATE}
        chown -R root:privatelab /srv/$HOSTNAME/sshkey/${HOSTNAME}_users/${USER,,}_${BACKUP_DATE}
        chmod 0750 /srv/$HOSTNAME/sshkey/${HOSTNAME}_users/${USER,,}_${BACKUP_DATE}
        cp $HOME_BASE/$USER/.ssh/id_${USER,,}_ed25519* /srv/$HOSTNAME/sshkey/${HOSTNAME}_users/${USER,,}_${BACKUP_DATE}/
        msg "Creating ${USER} smb account..."
        (echo ${PASSWORD}; echo ${PASSWORD} ) | smbpasswd -s -a $USER
        info "User '$USER' has been added to the system."
        echo
      fi
      # Chattr set user desktop folder attributes to +i
      while read dir
      do
        touch $HOME_BASE/$USER/$dir/.foo_protect
        chattr +i $HOME_BASE/$USER/$dir/.foo_protect
      done < <( ls $HOME_BASE/$USER )
    done < <( printf '%s\n' "${new_user_LIST[@]}" )

    #---- Email User SSH Keys
    if [ "$SMTP_STATUS" = 1 ]
    then
      section "Email User Credentials & SSH keys"
      echo
      msg_box "#### PLEASE READ CAREFULLY - EMAIL NEW USER CREDENTIALS ####\n
      You can email a new user's login credentials and ssh keys to the NAS system administrator. The NAS system administrator can then forward the email(s) to each new user.

      The email will include the following information and attachments:
        --  Username
        --  Password
        --  User Group
        --  Private SSH Key (Standard)
        --  Private SSH Key (PPK Version)
        --  SMB NAS Server connection credentials
        --  SMB Status
        --  SFTP NAS connection credentials
        --  Account type (folder access level)"
      echo
      while true
      do
        read -p "Email new users credentials & SSH key to your systems administrator [y/n]? " -n 1 -r YN
        echo
        case $YN in
          [Yy]*)
            while read USER PASSWORD GROUP USERMOD
            do
              source $DIR/email_templates/pve_nas_ct_newuser_msg.sh
              msg "Sending '$USER' credentials and ssh key package to '$PVE_ROOT_EMAIL'..."
              sendmail -t < email_body.html
              info "Email sent. Check your system administrators inbox."
            done < <( printf '%s\n' "${new_user_LIST[@]}" )
            break
            ;;
          [Nn]*)
            info "You have chosen to skip this step. Not sending any email(s)."
            echo
            break
            ;;
          *)
            warn "Error! Entry must be 'y' or 'n'. Try again..."
            echo
            ;;
        esac
      done
    fi
    echo
  else
    msg "No new users have been created."
    echo
  fi
fi


#---- Exit the script
if [ "$RESULTS" = TYPE00 ]
then
  msg "You have chosen not to proceed. Moving on..."
  echo
fi

#---- Finish Line ------------------------------------------------------------------

# Cleanup
if [ -z "${PARENT_EXEC+x}" ]
then
  trap cleanup EXIT
fi
#-----------------------------------------------------------------------------------