#!/bin/bash

# Removes old revisions of snaps that take up too much space.

# CLOSE ALL SNAPS BEFORE RUNNING THIS

set -eu

snap list --all | awk '/disabled/{print $1, $3}' |
  while read snapname revision; do
    snap remove "$snapname" --revision="$revision"
  done

# clean up journal logs
sudo journalctl --rotate
sudo journalctl --vacuum-size=50M
