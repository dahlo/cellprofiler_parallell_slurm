#!/bin/env python

# generates a .csv file that looks lika a ImageSetList from cellprofiler


import os
import sys
import glob
import re
from collections import defaultdict
import argparse

# from IPython.core.debugger import Tracer




parser = argparse.ArgumentParser(description='generates a .csv file that looks lika a ImageSetList from cellprofiler')
parser.add_argument('-i', 
                    '--input_dir', 
                    type=str, 
                    help='Input directory to recursivly search for images.', 
                    required=True)
parser.add_argument('-o', 
                    '--output_dir', 
                    type=str, 
                    help='Output directory where to place the image set file.', 
                    required=True)
parser.add_argument('-b', 
                    '--barcode',  
                    help='Barcode override, instead of using input folder name as barcode.')
parser.add_argument('-c', 
                    '--ch_names', 
                    help='Channel names override, will use a comma separated list of new channel names. Assigned in order given w1,w2,w3... Note: it will only create columns for as many channels you specify. Default: HOECHST,SYTO,MITO,CONCAVALIN,PHALLOIDINandWGA')

# todo?
# parser.add_argument('-r', action='store_true', default=False,
                    # dest='boolean_switch',
                    # help='Use to search the folder recursivly.')
# save the arguments
args = parser.parse_args()
#Tracer()()
if args.barcode:
    barcode_override = args.barcode

# Tracer()()


thumbnail_re = re.compile('_thumb')
imageinfo_re = re.compile('^(?P<Date>[0-9]{6})-(?P<Barcode>.*)_(?P<Well>[A-P][0-9]{2})_s(?P<Site>[0-9]+)_w(?P<ChannelNumber>[0-9])')
imageinfo_fallback_re = re.compile('^(?P<Barcode>.*)_(?P<Well>[A-P][0-9]{2})_s(?P<Site>[0-9]+)_w(?P<ChannelNumber>[0-9])')

# as per https://stackoverflow.com/questions/5369723/multi-level-defaultdict-with-variable-depth/8702435#8702435
nested_dict = lambda: defaultdict(nested_dict)
images = nested_dict()

# list everything in the dir
for file_path in glob.iglob(args.input_dir + '/**/*', recursive=True):
    
    # break out the file name only
    file_path = os.path.abspath(file_path)
    filename = os.path.basename(file_path)
    path = os.path.dirname(file_path)
    
    # only keep certain file endings
    file_ending = filename.split('.')[-1]
    if file_ending.lower() not in ['tif', 'tiff']:
        continue
        
    # skip thumbnails
    if thumbnail_re.search(filename):
        continue

    # pick out the image info
    match = imageinfo_re.match(filename)
#    Tracer()()
    if match:
        try:
            barcode = barcode_override
        except:
            barcode = match.group('Barcode')
        # save the info
        images[match.group('Date')][barcode][match.group('Well')][match.group('Site')][match.group('ChannelNumber')] = {'name':filename, 'path':path}
    else:
        # try a more generous regexp
        match = imageinfo_fallback_re.match(filename)
        if match:
            from datetime import datetime
            sys.stderr.write("WARNING: Unable to parse date and barcode from image file name ({}), falling back to a more relaxed pattern, using \"{}\" as barcode and {} as date.\n".format(filename, match.group('Barcode'), datetime.now().strftime('%y%m%d')))
            try:
                barcode = barcode_override
            except:
                barcode = match.group('Barcode')
            # save the info
            date=datetime.now().strftime('%y%m%d')
            images[date][barcode][match.group('Well')][match.group('Site')][match.group('ChannelNumber')] = {'name':filename, 'path':path}
        else:
            sys.exit(f"\n\nERROR when generating imageset list: file name not matching regexp pattern. File '{filename}'")
        # Tracer()()




# define channel names
if args.ch_names:
    # construct dict for specified channels
    ch_names = dict()
    for i,ch_name in enumerate(args.ch_names.split(',')):
        ch_names[f"w{i+1}"] = ch_name
else:
    ch_names = {'w1':'HOECHST', 'w2':'SYTO', 'w3':'MITO', 'w4':'CONCAVALIN', 'w5':'PHALLOIDINandWGA'}

### create header row
header = ""

for ch_nr,ch_name in sorted(ch_names.items()):
    header += f"FileName_{ch_nr}_{ch_name},"
    
header += "Group_Index,Group_Number,ImageNumber,Metadata_Barcode,Metadata_Site,Metadata_Well,"

for ch_nr,ch_name in sorted(ch_names.items()):
    header += f"PathName_{ch_nr}_{ch_name},"

for ch_nr,ch_name in sorted(ch_names.items()):
    header += f"URL_{ch_nr}_{ch_name},"

# remove last comma
header = header[:-1]
###    

imgset_counter = 1
content = ""
# for all images
for date in sorted(images):
    for barcode in sorted(images[date]):
        for well in sorted(images[date][barcode]):
            for site in sorted(images[date][barcode][well]):
                                
                # construct the csv row
                row = ""
                
                # add file names
                for ch_nr,file in sorted(images[date][barcode][well][site].items())[:len(ch_names)]:
                    row += file['name'] + ","
                   
                # add info
                row += f"{imgset_counter},1,{imgset_counter},{barcode},{site},{well},"
                
                # add file path
                for ch_nr,file in sorted(images[date][barcode][well][site].items())[:len(ch_names)]:
                    row += file['path'] + ","
                    
                # add file url
                for ch_nr,file in sorted(images[date][barcode][well][site].items())[:len(ch_names)]:
                    row += f"file:{file['path']}/{file['name']},"
                    
                # remove last comma
                row = row[:-1]
                
                # add it to the content
                content += row+"\n"
                
                # increase counter
                imgset_counter += 1


    
# write the file
with open(f"{args.output_dir}/ImageSetList_{barcode}.csv", 'w') as output:
    output.write(header+"\n")
    output.write(content)

print(f"{args.output_dir}/ImageSetList_{barcode}.csv")



