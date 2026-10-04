# Android Phone as Mac Webcam

## Core Purpose
Plug in an Android phone with a USB cable, pick a phone camera (front or any rear lens), and see it as a camera in Photo Booth, QuickTime, WhatsApp (desktop and web) on the Mac.

## Architecture
Phone camera -> H.264 encoder -> TCP server on phone (port 5000)
   -> USB cable (adb forward) ->
Mac Camera Extension -> TCP client -> VideoToolbox decoder -> virtual camera -> apps

## Latency Target
Under 100 ms is a stretch goal. Realistic result is 100-200 ms.
