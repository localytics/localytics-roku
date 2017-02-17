#!/bin/bash
find . -type f | grep -v *.zip | grep -v ".idea" | grep -v "sample.iml" | grep -v build.sh | xargs zip roku
