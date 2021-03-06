## Code for figure 4 (raw format)

## Usage
# module load R/3.3
# mkdir -p logs
# Rscript figure4.R > logs/figure4_log.txt 2>&1
library('derfinder')
library('derfinderPlot')
library('GenomicRanges')

## Load pheno data
load("/users/ajaffe/Lieber/Projects/Grants/Coverage_R01/brainspan/brainspan_phenotype.rda")
## Drop bad samples
bad_samples <- which(rownames(pdSpan) %in% c('216', '218', '219'))
if(nrow(pdSpan) == 487) pdSpan <- pdSpan[-bad_samples, ]
stopifnot(nrow(pdSpan) == 484)

## Identify sample files
files <- pdSpan$wig
## Use backup files
files <- gsub('/nexsan2/disk3/ajaffe/BrainSpan/RNAseq/bigwig',
    '/dcl01/lieber/ajaffe/derRuns/BrainSpan_bigwig_backup', files)

## Sample names
names(files) <- pdSpan$lab

## Can it open the first file?
bw <- files[1]
system(paste('ls -lh', bw))
stopifnot(file.exists(bw))

## Load previous info
path <- "/dcl01/lieber/ajaffe/derRuns/derSupplement/brainspan/derAnalysis/run5-v1.5.30/"
load(paste0(path, "groupInfo.Rdata"))

## Define region of interest
region <- GRanges(seqnames = 'chr3', ranges = IRanges(start = 57123500, end = 57131500))
data(hg19Ideogram, package = 'biovizBase')
seqlengths(region) <- seqlengths(hg19Ideogram)['chr3']

## Get coverage
fullCov <- fullCoverage(files = files, chrs = 'chr3', mc.cores = 1,
    which = region, protectWhich = 0, chrlens = seqlengths(region))

## Load annotation info
load('/dcl01/lieber/ajaffe/derRuns/derfinderExample/derGenomicState/GenomicState.Hsapiens.UCSC.hg19.knownGene.Rdata')
library('bumphunter')
library('TxDb.Hsapiens.UCSC.hg19.knownGene')
genes <- annotateTranscripts(txdb = TxDb.Hsapiens.UCSC.hg19.knownGene)

## Annotate regions
annotated <- annotateRegions(regions = region,
	genomicState = GenomicState.Hsapiens.UCSC.hg19.knownGene$fullGenome,
    minoverlap = 1)
annotation <- matchGenes(x = region, subject = genes)

## Get the region coverage
regionCov <- getRegionCoverage(fullCov = fullCov, regions = region,
	verbose = FALSE)
tIndexes <- split(seq_len(length(groupInfo)), groupInfo)
regionCovMeans = lapply(regionCov, function(x) {
	cat(".")
	sapply(tIndexes, function(ii) rowMeans(x[,ii]))
})

## Panel 1: mean by group
dir.create('plots', showWarnings = FALSE)
pdf('plots/figure4_raw.pdf', h = 5, w = 7)
plotRegionCoverage(regions = region, 
	regionCoverage = regionCovMeans,
	groupInfo = factor(levels(groupInfo), levels = levels(groupInfo)), 
	nearestAnnotation = annotation,
	annotatedRegions = annotated,
	ask=FALSE,	verbose=FALSE, 
	txdb = TxDb.Hsapiens.UCSC.hg19.knownGene, ylab = 'Mean coverage')
dev.off()

## Reproducibility info
proc.time()
message(Sys.time())
options(width = 120)
devtools::session_info()
