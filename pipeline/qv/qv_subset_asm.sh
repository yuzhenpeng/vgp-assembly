#!/bin/bash

if [ -z $1 ]; then
	echo "Usage: ./qv_subset_asm.sh <genome_id> <fasta.fai>"
	echo -e "\tExtract variant calls for <fasta.fai> and get the QV only for those"
	exit -1
fi

genome=$1
fai=$2
hap=${fai/.fai/}
hap=${hap/.fasta/}

threads=$SLURM_CPUS_PER_TASK
if [ -z $threads ]; then
	threads=2
fi

echo "Load modlues"
module load bedtools
module load samtools
echo

if [ ! -e $genome.changes.vcf.gz ]; then
	echo "Get changes"
	echo "\
	bcftools view -i 'QUAL>1 && (GT="AA" || GT="Aa")' -Oz --threads=$threads $genome.bcf > $genome.changes.vcf.gz"
	bcftools view -i 'QUAL>1 && (GT="AA" || GT="Aa")' -Oz --threads=$threads $genome.bcf > $genome.changes.vcf.gz
	echo "\
	bcftools index $genome.changes.vcf.gz"
	bcftools index $genome.changes.vcf.gz
	echo
fi

awk '{print $1"\t0\t"$2}' $fai > $hap.bed


echo "Collect $genome.$hap.numvar"
bcftools view -H -R $hap.bed $genome.changes.vcf.gz | awk -F "\t" '{print $4"\t"$5}' | awk '{lenA=length($1); lenB=length($2); if (lenA < lenB ) {sum+=lenB-lenA} else if ( lenA > lenB ) { sum+=lenA-lenB } else {sum+=lenA}} END {print sum}' > $hap.numvar
echo "Num. bases affected: `cat $hap.numvar`"
echo


echo "Collect $hap contigs/scaffold names"
cut -f1 $hap.bed > $hap.list
echo

if [[ -e summary.csv ]]; then
	mean_cov=`tail -n1 summary.csv | awk -F "," '{printf "%.0f\n", $17}'`   # parse out the mean_cov from summary.csv
	h=$((mean_cov*12))
else
	h=600
	echo "No summary.txt found. Set h to $h for filtering out high coverage regions"
fi

echo "\
java -jar -Xmx1g $VGP_PIPELINE/utils/txtContains.jar aligned.genomecov $hap.list 1 | awk -v h=$h'{if (\$2>3 && \$2<h) {numbp+=\$3}} END {print numbp}' - > $hap.numbp"
java -jar -Xmx1g $VGP_PIPELINE/utils/txtContains.jar aligned.genomecov $hap.list 1 | awk -v h=$h '{if ($2>3 && $2<h) {numbp+=$3}} END {print numbp}' - > $hap.numbp


NUM_BP=`cat $hap.numbp`
echo "Total bases > 3x: in $hap: $NUM_BP"
NUM_VAR=`cat $hap.numvar`
echo "Total num. bases subject to change in $hap: $NUM_VAR"
QV=`echo "$NUM_VAR $NUM_BP" | awk '{print (-10*log($1/$2)/log(10))}'`
echo $QV > $hap.qv
echo "QV of this genome $genome $hap: $QV"
echo

