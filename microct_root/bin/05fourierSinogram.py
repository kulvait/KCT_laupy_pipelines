#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Created on Wed May	8 12:59:30 2019

@author: Vojtech Kulvait

This scripts creates Fourier sinogram
"""
import argparse
import glob
import os
import sys
import shutil
import pydicom
import re
import h5py
from pathlib import Path
from denpy import DICOM
from denpy import PETRA
from denpy import UTILS
from numpy.fft import fft2
import matplotlib.pyplot as plt
import numpy as np

# processDir = '/mnt/md1337/CTPerfusionData/MagdeburgII'

def createFourierPlot(directory, sinogramFile, cropLeft=0, cropRight=0):
	if not os.path.isdir(directory, sinogramFile):
		return {}
	df = PETRA.imageDataset(os.path.join(directory, "h5"))
	df = df.sort_values("s_rot")
	x = DEN.getFrame(os.path.join(directory, sinogramFile))
	x = x[list(df["frame_ind"])]
	if cropLeft > 0:
		x = x[cropLeft:]
	if cropRight > 0:
		x =x[-cropRight:]
	f = fft2(x)
	g = plt.abs(f)
	plt.imshow(g, vmin=np.quantile(g, 0.01), vmax=np.quantile(g, 0.99))
	plt.show()

import argparse
parser = argparse.ArgumentParser()
parser.add_argument("inputDir")
parser.add_argument("inputSinogram")
parser.add_argument("--pattern", default=None)
parser.add_argument("--crop-left", type=int, default=0)
parser.add_argument("--crop-right", type=int, default=0)
parser.add_argument("--force", action="store_true")
parser.add_argument("--singledir", action="store_true")
parser.add_argument("--dry-run", action="store_true")
ARG = parser.parse_args()
rawDir = ARG.rawDir

if ARG.singledir:
	subDirs = [inputDir]
else:
	subDirs = next(os.walk(inputDir))[1]
	subDirs = [os.path.join(inputDir, x) for x in subDirs]

if ARG.pattern is None:
	regexp = None
else:
	regexp = re.compile(ARG.pattern)

for d in subDirs:
	if regexp is not None and regexp.search(d) is None:
		continue
	createFourierPlot(d, ARG.inputSinogram, ARG.crop_left, ARG.crop_right)
