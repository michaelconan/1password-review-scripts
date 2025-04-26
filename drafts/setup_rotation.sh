#!/bin/bash

VAULT=private

# retrieve all logins from the private vault
logins=$(op item list --categories Login --format json --vault $VAULT | jq -r '.[]')

# loop through each login
for login in $logins; do

    # get the login password field if exists
    login_info=$(op item get $login --format json)
    # identify password field using id
    login_password=$(echo $login_info | jq -r '.fields[] | select(.id == "password")')
    # identify custom fields using labels
    login_fields=$(echo $login_info | jq -r '.fields[].label')
    
    # check if the login has a password field
    if [[ -n $login_password ]]; then
        # check if password rotation field does not exist
        if [[ ! ${login_fields[@]} =~ "last password update" ]]; then
            # set initial password update to item created date
            created_date=$(echo $login_info | jq -r '.created_at' | cut -d 'T' -f 1)
            op item edit $login "rotation.last password update[date]=$created_date"
        fi
    fi
    
done
