#!/bin/sh

base="/home/blobb/develop/test_croni/croni-test"
project="tests"
job="test_fail"

number="214"
default_build_rotation="28"
default_workspace_rotation="14"

number="$((number - default_build_rotation))"
while [ -f "$base/logs/$project/$job/${job}_${number}.log" ]; do
  echo "Deleting: $base/logs/$project/$job/${job}_${number}.log"
  rm "$base/logs/$project/$job/${job}_${number}.log"
  number=$((number-1))
done

number="214"
number="$((number - default_workspace_rotation))"
while [ -d "$base/logs/$project/$job/workspaces/$number" ]; do
  echo "$base/logs/$project/$job/workspaces/$number"
  rm -rf "$base/logs/$project/$job/workspaces/$number"
  number=$((number-1))
done


# /home/blobb/develop/test_croni/croni-test/logs/tests/test_fail
