#!/bin/bash

REPO_URL="https://raw.githubusercontent.com/LineageOS/android_system_core"
REPO_BRANCH="cm-14.1"
BASE_DIR="mkbootimg"
FILES=( mkbootimg unpackbootimg )

for file in ${FILES[@]}; do
	wget "${REPO_URL}/${REPO_BRANCH}/${BASE_DIR}/$file" -O "bin/$file"

	# add copyrights for LineageOS
	sed -i s/'Copyright 2015, The Android Open Source Project'/'Copyright 2015, The Android Open Source Project\n# Copyright (C) 2015-2016 The CyanogenMod Project\n# Copyright (C) 2017 The LineageOS Project'/g "bin/$file"
done


