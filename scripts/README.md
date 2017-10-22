Extract PepperFlash from ChromeOS recovery images
=================================================

These scripts will extract PepperFlash from Google's official ChromeOS recovery
images (preferably Acer Chromebook 13 images).

The process is based on the [linux_recovery.sh](https://dl.google.com/dl/edgedl/chromeos/recovery/linux_recovery.sh) script.
For more information, see: https://support.google.com/chromebook/answer/1080595?hl=en


Use `extract-flash.sh`
----------------------

Use this script to
- Download the latest Acer Chromebook 13 recovery image
- Extract it
- Mount the ROOT-A partition
- Extract PepperFlash

This script shares no code with the official `linux_recovery.sh`.
Everything is reimplemented.

**You are using this script on your own behalf!**

To *run* this script, simply execute
``` bash
# cd /path/to/here && ./extract-flash.sh
```
