#!/bin/bash

set -e
set -o pipefail

#   Define usage message
function usage() {
    echo -e "\
$0: \n\
\n\
Usage: ./LD_data_prep.sh [snp_bac] [genotype_data] [out_prefix] [work_dir] \n\
\n\
NOTE: arguments must be provided in this order! \n\
\n\
where: \n\
1. [snp_bac] is a file that includes the Query_SNP name and physical position \n\
2. [genotype_data] is a file that has genotype data \n\
3. [out_prefix] is what prefix will our output filename look like? \n\
4. [work_dir] is where we want to output our files? \n\
" >&2
exit 1
}

if [[ $# -lt 3 ]]; then usage; fi

if ! $(command -v Rscript > /dev/null 2> /dev/null); then echo "Failed to find R, exiting..." >&2; exit 1; fi
if ! $(command -v perl > /dev/null 2> /dev/null); then echo "Failed to find Perl, exiting..." >&2; exit 1; fi

#   Generate sample lists
function sampleList() {
    local snp_bac=$1
    local out_prefix=$2
    local work_dir=$3
    #   Sort SNP_BAC.txt file by Query_SNP columns
    #   Only keep unique SNP names
    (head -n 1 ${snp_bac} && tail -n +2 ${snp_bac} | sort -u -k1,1) > ${work_dir}/SNP_BAC_${out_prefix}_sorted_uniq.txt
    #   Generate sample lists
    for i in $(awk '{ print $1 }' ${work_dir}/SNP_BAC_${out_prefix}_sorted_uniq.txt | tail -n +2); do echo "X$i"; done > ${work_dir}/${out_prefix}_sampleList.txt
}

export -f sampleList

#   extraction_SNPs.pl to pull out markers of interest
#   Arguments required: (1) WBDC_genotype_count.txt, (2) Sample_names_list.txt
function extractSNPs() {
    local extraction=$1
    local geno=$2
    local sample_names=$3
    local out_prefix=$4
    local work_dir=$5
    #   Use Perl script to pull down markers of interest
    #   and create new dataframe
    ${extraction} ${geno} ${sample_names} | \
        #   Markers in both genotype dataframe and sample list
        tee >(grep -v "NOT_EXISTS" > ${work_dir}/${out_prefix}_EXISTS.txt) | \
        #   Markers that are not in genotype dataframe are redirected to new file
        grep "NOT_EXISTS" | tee ${work_dir}/${out_prefix}_NOT_EXISTS.txt | \
        #   How many SNPs were not found in dataframe?
        echo "$(wc -l) SNPs did not exist in dataframe"
}

export -f extractSNPs

#   Sort data prior to feeding to LDheatmap.R
function sortData() {
    local exists=$1
    local out_prefix=$2
    local work_dir=$3
    #   Sort dataframe output from extractSNPs
    #   with SNPs as rows and individual names as columns
    awk 'NR<2{ print $0;next }{ print $0 | "sort -k 1n,1" }' ${exists} > ${work_dir}/${out_prefix}_sorted_EXISTS.txt
}

export -f sortData

#   Arguments provided by user
SNP_BAC=$1 # snpBAC.txt pulled from HarvEST
GENO=$2 # Genotype Data
OUT_PREFIX=$3 # output file prefix
WORK_DIR=$4 # where is our working directory?

#   Script filepaths
#   Please provide full filepaths to scripts
EXTRACTION='/home/chaochih/C/Users/chaoc/GitHub/Barley_Inversions/scripts/LD_Analysis/extraction_SNPs.pl'
LD_HEATMAP='/home/chaochih/C/Users/chaoc/GitHub/Barley_Inversions/scripts/LD_Analysis/LDheatmap.R'

#   Arguments generated by functions
SAMPLE_NAMES=${WORK_DIR}/${OUT_PREFIX}_sampleList.txt # List of samples names
EXISTS=${WORK_DIR}/${OUT_PREFIX}_EXISTS.txt # SNPs we have genotype data for
GENO_SORTED=${WORK_DIR}/${OUT_PREFIX}_sorted_EXISTS.txt # genotype data frame with SNPs sorted
SNP_BAC_SORTED=${WORK_DIR}/SNP_BAC_${OUT_PREFIX}_sorted.txt # Sorted HarvEST SNP_BAC.txt file with PhysPos and Chr 2016 columns

#   Generate sample lists
sampleList ${SNP_BAC} ${OUT_PREFIX} ${WORK_DIR}
#   Outputs dataframe with SNPs as columns and sample names as rows
extractSNPs ${EXTRACTION} ${GENO} ${SAMPLE_NAMES} ${OUT_PREFIX} ${WORK_DIR}
#   Sort dataframes and pull out unique SNPs
sortData ${EXISTS} ${OUT_PREFIX} ${WORK_DIR}

EXIT_STATUS=1
while [[ EXIT_STATUS -ne 0 ]]
do
    Rscript 2> errmsg.txt # save error messages
    EXIT_STATUS=$0
    # error handling
done
