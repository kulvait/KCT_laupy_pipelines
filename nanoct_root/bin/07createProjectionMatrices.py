#!/usr/bin/env python
"""
Created on Wed Jul	12 2023

@author: Vojtech Kulvait

This script produces camera matrices for given dataset based on H5 file and provided dimensions of pixels

"""

import argparse
import glob
import os
import errno
import sys
import h5py
import math
import re
from denpy import DEN
from denpy import UTILS
from denpy import PETRA
import numpy as np
import scipy
from scipy.ndimage import gaussian_filter
from scipy.signal import savgol_filter


parser = argparse.ArgumentParser()
parser.add_argument("inputH5", help="H5 file with dataset information")
parser.add_argument("outputProjectionMatrices", help="H5 file with dataset information")
parser.add_argument("--rotation-center-offset", default=0.0, help="Offset of the rotation center, defaults to 0")
parser.add_argument("--detector-center-offsetvx", type=float, default=0., help="Offset of the center of the detector, detector_center_offsetvx * VX + detector_center_offsetvy * VY is added to the coordinates of the center of the detector for each angle, defaults to 0.0.")
parser.add_argument("--detector-center-offsetvy", type=float, default=0., help="Offset of the center of the detector, detector_center_offsetvx * VX + detector_center_offsetvy * VY is added to the coordinates of the center of the detector for each angle, defaults to 0.0.")
parser.add_argument("--rotation-center-file", default=None, help="Use value stored in file to determine rotation center")
parser.add_argument("--pixel-sizex", default=None, type=float, help="Pixel size x to use for projection geometry.")
parser.add_argument("--pixel-sizey", default=None, type=float, help="Pixel size y to use for projection geometry.")
parser.add_argument("--detector-sizex", default=None, help="If there is input file, this is ignored and dimx used instead")
parser.add_argument("--detector-sizey", default=None, help="If there is input file, this is ignored and dimy used instead")
parser.add_argument("--input-file", default=None, help="DEN file with projections to create corresponding projection matrices, if there is not detector size information, nor input file specified, dimensions of the camera from h5 file are used instead.")
parser.add_argument("--material-ct-convention", action="store_true", default=True, help="The z axis direction and PY direction will coincide, that is usually not the case in medical CT praxis. See also https://kulvait.github.io/KCT_doc/posts/tomographic-notes-1-geometric-conventions.html.")
parser.add_argument("--flat-matrices", help="Create 1D projection matrices.", action="store_true")
parser.add_argument("--verbose", action="store_true")
parser.add_argument("--petra-compatibility-transform", action="store_true", help="Make geometry compatible with that used by JM in his reconstruction scripts")
parser.add_argument("--log-file", default=None, help="Output to log file insted of stdout")
parser.add_argument("--force", action="store_true")
parser.add_argument("--write-params-file", action="store_true")
parser.add_argument('--_json-message', default="Created using KCT script createCameraMatricesForCircularScanTrajectoryParallelRay3D.py", help=argparse.SUPPRESS)
ARG = parser.parse_args()

if ARG.log_file:
	sys.stdout = open(ARG.log_file, "wt")

df = PETRA.imageDataset(ARG.inputH5, includePixelShift=True)
h5 = h5py.File(ARG.inputH5, 'r')

#Solution from https://stackoverflow.com/a/55114771
def checkFileExistence(f):
	if os.path.exists(f):
		if os.path.isfile(f):
			if ARG.force:
				os.remove(f)
				return
			else:
				print("File %s exist, add --force to proceed."%f)
				sys.exit(1)
		else:
			print("Path %s exist remove to proceed.", f)
			sys.exit(1)

checkFileExistence(ARG.outputProjectionMatrices)
if ARG.write_params_file:
	checkFileExistence(paramsFile)
	paramsFile="%s.params"%(ARG.outputProjectionMatrices)

pix_sizecam = float(h5["entry/hardware/camera1/pixelsize"][0])
pix_sizemag = float(h5["entry/hardware/camera1/magnification"][0])
default_pixel_size = float(pix_sizecam/pix_sizemag)
default_detector_sizex = int(h5["entry/hardware/camera1/sensorsize_x"][0])
default_detector_sizey = int(h5["entry/hardware/camera1/sensorsize_y"][0])

#If there is nothing else specified
pixel_sizex = default_pixel_size
pixel_sizey = default_pixel_size
if ARG.pixel_sizex is not None:
	pixel_sizex = ARG.pixel_sizex
if ARG.pixel_sizey is not None:
	pixel_sizey = ARG.pixel_sizey

detector_sizex = default_detector_sizex
detector_sizey = default_detector_sizey
if ARG.detector_sizex is not None:
	detector_sizex = int(ARG.detector_sizex)
if ARG.detector_sizey is not None:
	detector_sizey = int(ARG.detector_sizey)
if ARG.input_file is not None:
	header = DEN.readHeader(ARG.input_file)
	if len(header["dimspec"]) != 3:
		raise TypeError("Dimension of dimspec for file %s shall be 3 but is %d!"%(arg.input_file, len(header["dimspec"])))
	dimspec = header["dimspec"]
	detector_sizex = np.uint32(dimspec[0])
	detector_sizey = np.uint32(dimspec[1])
	zdim = np.uint32(dimspec[2])
	if zdim != len(df):
		raise TypeError("Number of projections in %s shall be %d according to H5 file but is %d!"%(arg.input_file, len(df), zdim ))

#Now we compute if there is some offset e.g. due to the binning and correct for it
#We expect that top left corner of the detector matches top left of the camera

default_center_coord = (default_detector_sizex*0.5 - 0.5)*default_pixel_size
print("detector_sizex=%s pixel_sizex=%f"%(detector_sizex, pixel_sizex))
center_coord = (float(detector_sizex)*0.5 - 0.5)*pixel_sizex

rotation_center_offset = ARG.rotation_center_offset
if ARG.rotation_center_file is not None:
	rcf = open(ARG.rotation_center_file, 'r')
	for x in rcf.readlines():
		if re.search("^rotation_center_offset_pix=", x):
			rotation_center_offset_pix = float(x.rsplit("=",1)[1])
			rotation_center_offset = rotation_center_offset_pix * default_pixel_size
			break

totalCenterOffsetx = center_coord - default_center_coord + rotation_center_offset + ARG.detector_center_offsetvx
totalCenterOffsety = ARG.detector_center_offsetvx

#Now code analogous to createCameraMatricesForCircularScanTrajectoryParallelRay3D.py

#Direction so that theta is ccw to the X axis, returns unit vector
def rayDirection(theta):
	return(np.array([np.sin(theta), -np.cos(theta), 0.], dtype=np.float64))

def degToRad(angle):
	return np.pi*angle/180


#PETRA compatibility transform
def JTransform(angle):
	return -angle - 0.5*np.pi

M=float(detector_sizey)
N=float(detector_sizex)
PX=pixel_sizex
PY=pixel_sizey
print("M=%d N=%d PX=%f PY=%f"%(M, N, PX, PY))
directionAngles = df["s_rot"]
directionAngles = [degToRad(x) for x in directionAngles]
if ARG.petra_compatibility_transform:
	directionAngles = [JTransform(x) for x in directionAngles]

if ARG.flat_matrices:
	CameraMatrices = np.zeros((0,1,4), dtype=np.float64)
	for i in range(len(directionAngles)):
		theta = float(directionAngles[i])
	#	print("For i=%d theta=%0.5fpi"%(i,theta/np.pi))
		VR = rayDirection(theta)
		VX = np.array([np.cos(theta)*PX, np.sin(theta)*PX, 0.0], dtype=np.float64)
		a = np.array([np.cos(theta)/PX, np.sin(theta)/PX, 0.0], dtype=np.float64)
		detectorCenter=np.array([0.0,0.0,0.0], dtype=np.float64) + (VX/PX) * (-totalCenterOffsetx + df["pixel_shift"].iloc[i]*default_pixel_size)
	#	print("Shifting detector center by %f including rotation_center_offset=%f and pixel_size_x=%f"%(totalCenterOffsetx + df["pixel_shift"].iloc[i]*default_pixel_size, rotation_center_offset/default_pixel_size, pixel_sizex))
		px0 = N * 0.5 - 0.5 - detectorCenter.dot(a)
		CM = np.array([np.append(a, px0)])
		CM.shape=(1,1,4)
		CameraMatrices = np.concatenate((CameraMatrices, CM))
else:
	CameraMatrices = np.zeros((0,2,4), dtype=np.float64)
	for i in range(len(directionAngles)):
		theta = float(directionAngles[i])
	#	print("For i=%d theta=%0.5fpi"%(i,theta/np.pi))
		VR = rayDirection(theta)
		VX = np.array([np.cos(theta)*PX, np.sin(theta)*PX, 0.0], dtype=np.float64)
		a = np.array([np.cos(theta)/PX, np.sin(theta)/PX, 0.0], dtype=np.float64)
		if ARG.material_ct_convention:
			VY = np.array([0.0, 0.0, PY], dtype=np.float64)
			b = np.array([0.0, 0.0, 1.0/PY], dtype=np.float64)
		else:
			VY = np.array([0.0, 0.0, -PY], dtype=np.float64)
			b = np.array([0.0, 0.0, -1.0/PY], dtype=np.float64)
		detectorCenter=np.array([0.0,0.0,0.0], dtype=np.float64) + (VX/PX) * (-totalCenterOffsetx + df["pixel_shift"].iloc[i]*default_pixel_size) + (VY/PY) * totalCenterOffsety
	#	print("Shifting detector center by %f including rotation_center_offset=%f and pixel_size_x=%f"%(totalCenterOffsetx + df["pixel_shift"].iloc[i]*default_pixel_size, rotation_center_offset/default_pixel_size, pixel_sizex))
		px0 = N * 0.5 - 0.5 - detectorCenter.dot(a)
		py0 = M * 0.5 - 0.5 - detectorCenter.dot(b)
		CM = np.array([np.append(a, px0), np.append(b,py0)])
		CM.shape=(1,2,4)
		CameraMatrices = np.concatenate((CameraMatrices, CM))

DEN.storeNdarrayAsDEN(ARG.outputProjectionMatrices, CameraMatrices, ARG.force)

if ARG.write_params_file:
	with open(paramsFile, 'w') as f:
		json.dump(ARG.__dict__, f, indent=2, sort_keys=True)
