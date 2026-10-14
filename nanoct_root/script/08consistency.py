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
from denpy import DEN
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
parser.add_argument("inputFile", help="Input extinctions file.")
parser.add_argument("outputFile", help="Output extinctions file")
parser.add_argument("--plot", action="store_true")
parser.add_argument("--plot-with-angles", action="store_true")
parser.add_argument("--force", action="store_true")
parser.add_argument("--input-h5", default=None, help="H5 file with dataset information")
ARG = parser.parse_args()
header = DEN.readHeader(ARG.inputFile)
if len(header["dimspec"]) != 3:
	raise TypeError("Dimension of dimspec for file %s shall be 3 but is %d!"%(arg.input_file, len(header["dimspec"])))
dimspec = header["dimspec"]
detector_sizex = np.uint32(dimspec[0])
detector_sizey = np.uint32(dimspec[1])
zdim = np.uint32(dimspec[2])

projectionIndices = np.array(np.arange(zdim), dtype=np.float32)
means = np.zeros(zdim, dtype=np.float32)
directionAngles = None
if ARG.input_h5 is not None:
	df = PETRA.imageDataset(ARG.input_h5, includePixelShift=True)
	if zdim != len(df):
		raise TypeError("Number of projections in %s shall be %d according to H5 file but is %d!"%(arg.input_file, len(df), zdim ))
	directionAngles = df["s_rot"]


for k in range(zdim):
	f = DEN.getFrame(ARG.inputFile, k)
	means[k] = f.mean()
if ARG.plot_with_angles and directionAngles is not None:
	plt.plot(directionAngles, means)
	plt.show()
elif ARG.plot:
	plt.plot(projectionIndices, means)
	plt.show()

xmean = means.mean()
print("Will normalize to xmean=%f"%(xmean))
DEN.writeEmptyDEN(ARG.outputFile, dimspec, force=True)
for k in range(zdim):
	f = DEN.getFrame(ARG.inputFile, k)
	factor = xmean/f.mean()
	f = f * factor
	DEN.writeFrame(ARG.outputFile, k, f, force=True)
