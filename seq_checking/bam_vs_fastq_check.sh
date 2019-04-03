#!/bin/bash

set -e
set -o pipefail

#   Define usage message
function usage() {
    echo -e "\
$0: \n\
\n\
This script calls on a Python script, check_seq_id.py, to verify the correctness of SAM/BAM
file contents. It does this by comparing Illumina sequence identifiers present in the
SAM/BAM file to sequence identifiers in the FASTQ files. \n\
\n\
Usage: ./bam_vs_fastq_check.sh [aligned_list] [accession_names_list] [fastq_file_list] [fastq_suffix] [script_dir] [out_dir] [scratch_dir]\n\
\n\
NOTE: arguments must be provided in this order! \n\
\n\
where: \n\
1. [aligned_list] is a list of full filepaths to SAM/BAM files \n\
2. [accession_names_list] is a list of accession names separated by newline (one per line).
    Important: Make sure names (including case) matches names in [aligned_list].
    Ex: aligned filename is WBDC_336_realigned.bam, the accession name should
    then be 'WBDC_336'. \n\
3. [fastq_file_list] is a list of full filepaths to the raw FASTQ files used to generate
    SAM/BAM files. \n\
4. [fastq_suffix] is the suffix that matches raw FASTQ files (e.g., '.fastq.gz' or '.fq.gz') \n\
5. [script_dir] is the full filepath to where this script, bam_vs_fastq_check.sh, and the
    Python script, check_seq_id.py, are located. Please keep them in the same directory. \n\
6. [out_dir] is the full filepath to where we output our files. \n\
7. [scratch_dir] is the full filepath to where we want to store intermediate files. This
    can be the same as the [out_dir] but comes in handy since intermediate files can
    take up lots of storage space. \n\

Dependencies:
- Python3: >v3.7
- Samtools: >v1.8.0
- GNU Parallel
" >&2
exit 1
}

if [[ $# -lt 1 ]]; then usage; fi

# User provided input arguments
# List containing full filepaths to SAM or BAM files
ALIGNED_LIST=$1
# List of accession names only. Must match part of SAM/BAM and FASTQ filename.
ACC_LIST=$2
# List of FASTQ files that correspond to SAM/BAM samples
FASTQ_LIST=$3
# FASTQ files suffix (e.g., .fastq.gz)
# Note: This must match the suffix used in the FASTQ_LIST
FASTQ_SUFFIX=$4
# Full filepath to directory that contains our scripts
# Note: Please make sure bam_vs_fastq_check.sh and check_seq_id.py are in the same directory.
SCRIPT_DIR=$5
# Full filepath to directory to output files
OUT_DIR=$6
# Full filepath to scratch directory to temporarily store intermediate files
#   Note: This can be the same as the out directory but can be useful if you are running short
#   on storage space but have a scratch directory that doesn't count toward your storage.
SCRATCH_DIR=$7

# Check if out directories exists, if not create them
mkdir -p "${OUT_DIR}" \
         "${SCRATCH_DIR}" \
         "${SCRATCH_DIR}"/intermediates
# Because Python script uses append mode to save data to output files
# Clean out out directory here before starting (in case there are
# files from previous runs here)
rm "${OUT_DIR}"/*.txt
# Setup data structures
ACC_ARRAY=($(cat "${ACC_LIST}"))

function compare_seq_id() {
    local accession=$1
    local aligned_list=$2
    local fastq_list=$3
    local fastq_suffix=$4
    local script_dir=$5
    local out_dir=$6
    local scratch_dir=$7
    # Pull out aligned sample we are currently working with
    aligned=$(awk -v pat="${accession}" '$1 ~ pat {print}' ${aligned_list})
    # Pull out filepaths for forward and reverse reads for sample we are currently working with
    fastq_fwd=$(awk -v pat="${accession}" '$1 ~ pat {print}' ${fastq_list} | grep "R1")
    fastq_rev=$(awk -v pat="${accession}" '$1 ~ pat {print}' ${fastq_list} | grep "R2")

    # Pull out header lines from aligned file and store in file
    # Note: We are not working with the entire SAM/BAM file but instead pulling out the header
    # lines and Illumina sequence identifiers to significantly reduce the amount of data we
    # have to work with.
    samtools view -H "${aligned}" > "${scratch_dir}"/intermediates/"${accession}"_header_only.txt
    # Pull out Illumina sequence identifiers from aligned file and store in a file
    samtools view "${aligned}" | awk '{print $1}' > "${scratch_dir}"/intermediates/"${accession}"_seqIDs.txt

    # Call on Python script to make comparisons
    # [Placeholder]
    python3 "${script_dir}"/check_seq_id.py "${accession}" \
        "${scratch_dir}"/intermediates/"${accession}"_header_only.txt \
        "${scratch_dir}"/intermediates/"${accession}"_seqIDs.txt \
        "${fastq_fwd}" \
        "${fastq_rev}" \
        "${fastq_list}" \
        "${fastq_suffix}" \
        "${out_dir}"
}

export -f compare_seq_id

# Do the work
# (parallelize this part)
parallel compare_seq_id {} "${ALIGNED_LIST}" "${FASTQ_LIST}" "${FASTQ_SUFFIX}" "${SCRIPT_DIR}" "${OUT_DIR}" "${SCRATCH_DIR}" ::: "${ACC_ARRAY[@]}"
