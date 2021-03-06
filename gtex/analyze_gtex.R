## Original script: /users/ajaffe/Lieber/Projects/derfinderPaper/analyze_gtex.R
##
## Usage:
# qrsh -pe local 8
# mkdir -p logs
# module load R/3.3
# Rscript analyze_gtex.R > logs/analyze_gtex_log.txt 2>&1
library('derfinder')
library('derfinderPlot')
library('GenomicRanges')
library('rafalib')
library('GenomeInfoDb')
library('devtools')
getPcaVars = function(pca)  signif(((pca$sdev)^2)/(sum((pca$sdev)^2)),3)*100
ss = function(x, pattern, slot=1,...) sapply(strsplit(x,pattern,...), "[", slot)

## Create dir for saving rdas and plots to preserve structure from the original script
dir.create('rdas', recursive = TRUE, showWarnings = FALSE)
dir.create('plots', recursive = TRUE, showWarnings = FALSE)

# get the f statistic from 2 lmFit objects
getF = function(fit, fit0, theData) {
	
	rss1 = rowSums((fitted(fit)-theData)^2)
	df1 = ncol(fit$coef)
	rss0 = rowSums((fitted(fit0)-theData)^2)
	df0 = ncol(fit0$coef)

	fstat = ((rss0-rss1)/(df1-df0))/(rss1/(ncol(theData)-df1))
	f_pval = pf(fstat, df1-df0, ncol(theData)-df1,lower.tail=FALSE)
	fout = cbind(fstat,df1-df0,ncol(theData)-df1,f_pval)
	colnames(fout)[2:3] = c("df1","df0")
	fout = data.frame(fout)
	return(fout)
}

# load processed data
load('/dcl01/lieber/ajaffe/derRuns/derSupplement/gtex/regionMat-cut5.Rdata')
load("/dcl01/lieber/ajaffe/derRuns/derSupplement/gtex/gtex_pheno_with_mapped.Rdata")
## Should be the same:
stopifnot(identical(match(colnames(regionMat[[1]]$coverageMatrix), pd2$sra_accession), seq_len(ncol(regionMat[[1]]$coverageMatrix))))
pd2$Tissue <- pd2$SMTS
pd2$SubjectID <- pd2$SUBJID

## Check that we have the same number of samples per tissue
stopifnot(table(pd2$Tissue) - max(table(pd2$Tissue)) == 0)

### extract coverage data
regions = unlist(GRangesList(lapply(regionMat, '[[', 'regions')))
names(regions) = NULL
regionMat = do.call("rbind", lapply(regionMat, '[[', 'coverageMatrix'))
rownames(regionMat) = names(regions) = paste0("er", 1:nrow(regionMat))

### filter out short DERs
keepIndex = width(regions) > 8
regionMat = regionMat[keepIndex,]
regions = regions[keepIndex]

#################
#### analysis ###

# transform and offset
y = log2(regionMat+1)

## width of regions
quantile(width(regions))

### annotate
## Genomic state created by https://github.com/nellore/runs/blob/master/gtex/DER_analysis/coverageMatrix/genomicState/hg38-genomicState.R
load('/dcl01/leek/data/gtex_work/runs/gtex/DER_analysis/coverageMatrix/genomicState/genomicState.Hsapiens.BioMart.ENSEMBLMARTENSEMBL.GRCh38.p5.Rdata')
gs_raw <- genomicState.Hsapiens.BioMart.ENSEMBLMARTENSEMBL.GRCh38.p5$fullGenome
gs <- renameSeqlevels(gs_raw, paste0('chr', seqlevels(gs_raw)))

## Do the seqlengths match?
stopifnot(max(abs(seqlengths(regions) - seqlengths(gs)[names(seqlengths(regions))])) == 0)

ensemblAnno = annotateRegions(regions,gs)
countTable = ensemblAnno$countTable

pdf(file = 'plots/venn-GRCh38.p5.pdf')
vennRegions(ensemblAnno, main = 'GTEx expressed regions by GRCh38.p5', counts.col = 'blue')
dev.off()

## annotation ####
dim(countTable)
annoClassList = list(strictExonic = 
	which(countTable[,"exon"] > 0 & countTable[,"intron"] == 0 &
		countTable[,"intergenic"] == 0),
	strictIntronic = 
	which(countTable[,"intron"] > 0 & countTable[,"exon"] == 0 &
		countTable[,"intergenic"] == 0),
	strictIntergenic = which(countTable[,"intergenic"] > 0 & countTable[,"exon"] == 0 &
    countTable[,"intron"] == 0),
	exonIntron = which(countTable[,"exon"] > 0 & countTable[,"intron"] > 0 &
		countTable[,"intergenic"] == 0))

annoClassList$All = 1:nrow(regionMat) # add all

## Explore numbers
sapply(annoClassList, length)
100 * sapply(annoClassList, length) / nrow(countTable)
cumsum(100 * sapply(annoClassList, length)[-5] / nrow(countTable))

# width by annotation
t(sapply(annoClassList, function(ii) quantile(width(regions[ii]))))

### PCA ###
pcList = lapply(annoClassList, function(ii) {
	cat(".")
	pc = prcomp(t(y[ii,]))
	pc$rot = NULL # drop rotations
	return(pc) 
})
pcVarMat = sapply(pcList, getPcaVars)
rownames(pcVarMat) = paste0("PC", 1:nrow(pcVarMat))
pc1Mat = sapply(pcList, function(x) x$x[,1])
pc2Mat = sapply(pcList, function(x) x$x[,2])

## plots
ind = c(1:3,5)
pdf(file = 'plots/pca-simple.pdf')
rafalib::mypar(2,2,cex.axis=1)
for(i in ind) boxplot(pc1Mat[,i] ~ pd2$Tissue, 
	main = colnames(pc1Mat)[i],
	ylab=paste0("PC1: ", pcVarMat[1,i], "% of Var Explain"))

for(i in ind) boxplot(pc2Mat[,i] ~ pd2$Tissue, 
	main = colnames(pc2Mat)[i],
	ylab=paste0("PC2: ", pcVarMat[2,i], "% of Var Explain"))
dev.off()
    
    
## Simple plots for PC1 and PC2 with some added color and text
pdf(file = 'plots/pca-plots-gtex.pdf', width = 14, height = 7)
cnames <- c('Strictly exonic ERs', 'Strictly intronic ERs')
rafalib::mypar(1,2,cex.axis=1)
for(i in ind[1:2]) {
    boxplot(pc1Mat[,i] ~ pd2$Tissue, main = cnames[i], ylab = '', cex.axis = 1.5, cex.main = 2)
    text(3, sum(range(pc1Mat[,i])) / 2, labels = paste0("PC1: ", pcVarMat[1,i], "%\nof Var Explain"), col = 'dodgerblue2', cex = 2, font = 2)
}

for(i in ind[1:2]) {
    boxplot(pc2Mat[,i] ~ pd2$Tissue, main = cnames[i], ylab = '', cex.axis = 1.5, cex.main = 2)
    text(3, sum(range(pc2Mat[,i])) / 2, labels = paste0("PC2: ", pcVarMat[2,i], "%\nof Var Explain"), col = 'dodgerblue2', cex = 2, font = 2)
}
dev.off()


library('RColorBrewer')
colors <- brewer.pal(3, 'Set1')
names(colors) <- c('Liver', 'Heart', 'Testis')
titles <- c('strictExonic' = 'Strictly exonic ERs', 'strictIntronic' = 'Strictly intronic ERs', 'strictIntergenic' = 'Strictly intergenic ERs', 'All' = 'All ERs')

pdf(file = 'plots/pca-PC1-vs-PC2_all.pdf')
rafalib::mypar(2,2,cex.axis=1)
for(i in ind) {
    plot(x = pc1Mat[,i], y = pc2Mat[, i], col = colors[pd2$Tissue], pch = 20, xlab = paste0("PC1: ", pcVarMat[1,i], "% of variance explained"), ylab = paste0("PC2: ", pcVarMat[2, i], "% of variance explained"), main = titles[colnames(pc2Mat)[i]])
    if(i == 1)
        legend(0.5, 0.5, names(colors), bty = 'n', lwd = 4, col = colors, cex = 2)
}
dev.off()

pdf(file = 'plots/pca-PC1-vs-PC2.pdf', width = 12, height = 6)
rafalib::mypar(1,2,cex.axis=1, cex.lab = 1.5, mar = c(3, 3, 1.6, 1.1))
for(i in ind) {
    plot(x = pc1Mat[,i], y = pc2Mat[, i], col = colors[pd2$Tissue], pch = 20, xlab = paste0("PC1: ", pcVarMat[1,i], "% of variance explained"), ylab = paste0("PC2: ", pcVarMat[2, i], "% of variance explained"), main = titles[colnames(pc2Mat)[i]], cex = 2, cex.main = 2)
    if(i == 1 | i == 5)
        legend(0.5, 0.5, names(colors), bty = 'n', lwd = 4, col = colors, cex = 2)
}
dev.off()




	
#################
## DE analysis ##
library('limma')
mod = model.matrix(~pd2$Tissue)
mod0 = model.matrix(~1, data=pd2)
fit = lmFit(y, mod)
eb = ebayes(fit)
fit0 = lmFit(y,mod0)
ff = getF(fit, fit0, y)

outStats = data.frame(log2FC_LiverVsHeart = fit$coef[,2],
	log2FC_TestesVsHeart = fit$coef[,3],
	pval_LiverVsHeart = eb$p[,2],
	pval_TestesVsHeart = eb$p[,3])
	
outStats$fstat = ff$fstat
outStats$fPval = ff$f_pval
outStats$fBonf = p.adjust(outStats$fPval, "bonferroni")

sapply(annoClassList, function(ii) sum(outStats$fBonf[ii] < 0.05))
sapply(annoClassList, function(ii) mean(outStats$fBonf[ii] < 0.05))

################################### 
### conditional analysis ##########
## intron ~ tissue + nearExon #####
## intergenic ~ tissue + nearExon #

# extract introns
intronMat = y[annoClassList[["strictIntronic"]],]
intronRegions = regions[annoClassList[["strictIntronic"]]]

# extract exons
exonMat = y[annoClassList[["strictExonic"]],]
exonRegions = regions[annoClassList[["strictExonic"]]]

# get exon nearest to each intron
ooExon = distanceToNearest(intronRegions, exonRegions)
exonMatMatch = exonMat[subjectHits(ooExon),]
exonRegionsMatch = exonRegions[subjectHits(ooExon)]

## Some might not be matching: potential flag for not using the correct annotation!
stopifnot(length(ooExon) == length(intronRegions))
stopifnot(max(queryHits(ooExon)) == length(ooExon))

# PC1 versus distance
pdf(file = "plots/PC1vsDistance.pdf")
plot(x = mcols(ooExon)$distance, y = pcList$strictIntronic$rot[, 1][queryHits(ooExon)], ylab = 'PC1', xlab = 'Distance to nearest exon', cex = 0.5)
reg1 <- lm(pcList$strictIntronic$rot[, 1][queryHits(ooExon)] ~ mcols(ooExon)$distance)
abline(reg1, col = 'orange')
plot(x = log(mcols(ooExon)$distance + 1), y = pcList$strictIntronic$rot[, 1][queryHits(ooExon)], ylab = 'PC1', xlab = 'Distance to nearest exon: log(x + 1)', cex = 0.5)
reg2 <- lm(pcList$strictIntronic$rot[, 1][queryHits(ooExon)] ~ log(mcols(ooExon)$distance + 1))
abline(reg2, col = 'orange')
dev.off()

# conditional regression
outStatsExon = matrix(NA, ncol = 2, nrow = nrow(intronMat))
for(i in 1:nrow(outStatsExon)) {
	if(i %% 1000 == 0) cat(".")
	f = lm(intronMat[i,] ~ 
			pd2$Tissue + exonMatMatch[i,])
	f0 = lm(intronMat[i,] ~ exonMatMatch[i,])
	outStatsExon[i,] = as.numeric(anova(f,f0)[2,5:6])
}
colnames(outStatsExon) = c("Fstat", "pval")
rownames(outStatsExon) = rownames(intronMat)
outStatsExon=as.data.frame(outStatsExon)

outStatsExon$nearExon <- outStatsExon$nearDist <- NA
outStatsExon$nearExon[queryHits(ooExon)] = rownames(exonMatMatch)
outStatsExon$nearDist[queryHits(ooExon)] = mcols(ooExon)$distance

## get gene symbol
library('GenomicFeatures')

## Get data from Biomart
#system.time(xx <- makeTxDbPackageFromBiomart(version = '0.99', maintainer = 'Leonardo Collado-Torres <lcollado@jhu.edu>', author = 'Leonardo Collado-Torres <lcollado@jhu.edu>', destDir = '~/'))

## Load info
sql_file <- "/users/lcollado/TxDb.Hsapiens.BioMart.ENSEMBLMARTENSEMBL.GRCh38.p5/inst/extdata/TxDb.Hsapiens.BioMart.ENSEMBLMARTENSEMBL.GRCh38.p5.sqlite"
TranscriptDb <- loadDb(sql_file)

## Fix seqlevels
seqlevels(TranscriptDb,force=TRUE) = c(1:22,"X","Y","MT")
seqlevels(TranscriptDb) = paste0("chr", c(1:22,"X","Y","M"))
ensGene = genes(TranscriptDb)

library('biomaRt')
ensembl = useMart("ENSEMBL_MART_ENSEMBL", # VERSION 83, hg38
	dataset="hsapiens_gene_ensembl",
	host="dec2015.archive.ensembl.org")
sym = getBM(attributes = c("ensembl_gene_id","hgnc_symbol"), 
	values=names(ensGene), mart=ensembl)
ensGene$Symbol = sym$hgnc_symbol[match(names(ensGene), sym$ensembl_gene_id)]
ensGene = ensGene[!grepl("^MIR[0-9]", ensGene$Symbol)] # drop mirs

## match
oo1 = findOverlaps(intronRegions, ensGene)
outStatsExon$intronSym = NA
outStatsExon$intronSym[queryHits(oo1)] = ensGene$Symbol[subjectHits(oo1)]
oo2 = findOverlaps(exonRegionsMatch, ensGene)
outStatsExon$exonSym = NA
outStatsExon$exonSym[queryHits(oo2)] = ensGene$Symbol[subjectHits(oo2)]
outStatsExon$sameGene = outStatsExon$intronSym == outStatsExon$exonSym 	

####### take signif
outStatsExon$bonf = p.adjust(outStatsExon$pval, "bonf")
outStatsExonSig = outStatsExon[outStatsExon$bonf < 0.05 & 
	outStatsExon$intronSym!="" & outStatsExon$sameGene,]
outStatsExonSig = outStatsExonSig[order(outStatsExonSig$pval),]

## boxplots
intronToPlot = intronMat[match(rownames(outStatsExonSig), rownames(intronMat)),]
exonToPlot = exonMat[match(outStatsExonSig$nearExon, rownames(exonMat)),]


conditionalIntron <- function(i, subset = FALSE) {
    if(subset) {
        if(i == 2) {
            ylim <- c(0, 9)
        } else if (i == 22) {
            ylim <- c(0, 6)
        } else if (i == 25) {
            ylim <- c(0, 10)
        }
    } else {
        ylim <- c(0, 12)
    }
	boxplot(intronToPlot[i,] ~ pd2$Tissue, ylim = ylim,
		ylab="Log2(Adjusted Coverage)",cex.axis=2, cex.lab=2, 
		main="Intronic ER", cex.main=2, outline=FALSE)
    points(x = jitter(tissueToNum[pd2$Tissue]), y = intronToPlot[i,], col = colors[pd2$Tissue], pch = 20, cex = 1.5)
	legend("top", paste0("p=",signif(outStatsExonSig$pval[i], 3)),cex=1.4)
	par(mar = c(5,3,3,2))
	boxplot(exonToPlot[i,] ~ pd2$Tissue, ylim = ylim,
		ylab="",cex.axis=2, cex.lab=2, 
		main="Nearest Exonic ER", cex.main=2, outline=FALSE)
    points(x = jitter(tissueToNum[pd2$Tissue]), y = exonToPlot[i,], col = colors[pd2$Tissue], pch = 20, cex = 1.5)
	mtext(paste(outStatsExonSig$intronSym[i], "-",
		round(outStatsExonSig$nearDist[i]/1000), "kb away"), 
		side=1, outer=TRUE, line = -2, cex=2)
}


tissueToNum <- c('Heart' = 1, 'Liver' = 2, 'Testis' = 3)

pdf("plots/conditional_intronic_ERs_subset.pdf", h=6, w=12)
par(mfrow = c(1,2))
for(i in c(2, 22, 25)) {
	if(i %% 100 == 0) cat(".")
	par(mar = c(5,6,3,0))
	conditionalIntron(i, subset = TRUE)
}
dev.off()

pdf("plots/conditional_intronic_ERs.pdf", h=6, w=12)
par(mfrow = c(1,2))
for(i in seq_len(700)) {
	if(i %% 100 == 0) cat(".")
	par(mar = c(5,6,3,0))
	conditionalIntron(i)
}
dev.off()


save(outStatsExon, outStatsExonSig, file="rdas/conditionalIntronicERs.rda")


#######
tt = table(outStatsExonSig$exonSym)
geneTab = data.frame(gene = names(tt), numErs = as.numeric(tt), 
	minP= outStatsExonSig$pval[match(names(tt), outStatsExonSig$intronSym)])
geneTab = geneTab[order(geneTab$numErs, -log10(geneTab$minP),decreasing=TRUE),]
rownames(geneTab) <- NULL
dim(geneTab)
geneTab

## make region plots
library('derfinderPlot')
library('RColorBrewer')
tIndexes = split(1:nrow(pd2), pd2$Tissue)
library('bumphunter')
genes <- annotateTranscripts(txdb = TranscriptDb)

## load full coverage
bw = pd2$sampleFile
names(bw) = pd2$sra_accession
fullCov = fullCoverage(bw, chrs = paste0("chr",c(1:22,"X","Y")), mc.cores = 8)

## Annotate regions
top <- seq_len(60)
geneRegions = ensGene[match(geneTab$gene[top], ensGene$Symbol)]
annotatedGeneRegions <- annotateRegions(regions = geneRegions,
	genomicState = gs, minoverlap = 1)

## Find nearest annotation with bumphunter::matchGenes()
nearestAnnotation <- matchGenes(x = geneRegions, subject = genes)
nearestAnnotation$name = geneTab$gene[top]

## Get the region coverage
geneRegionCov <- getRegionCoverage(fullCov=fullCov, regions=geneRegions,
	targetSize = 4e+07, totalMapped = pd2$totalMapped)
geneRegionCovMeans = lapply(geneRegionCov, function(x) {
	cat(".")
	sapply(tIndexes, function(ii) rowMeans(x[,ii]))
})

pdf('plots/GTEX_topERs.pdf', h = 5, w = 7)
plotRegionCoverage(regions=geneRegions, 
	regionCoverage=geneRegionCovMeans,
	groupInfo=factor(names(tIndexes), levels = c('Liver', 'Heart', 
        'Testis')), colors = brewer.pal(3, 'Set1'), 
	nearestAnnotation=nearestAnnotation,
	annotatedRegions=annotatedGeneRegions,
	ask=FALSE,	verbose=FALSE, 
	txdb = TranscriptDb)
dev.off()

## Find genes with a lot of intronic ERs
tt_intron <- table(outStatsExon$intronSym)
intronTab <- data.frame(gene = names(tt_intron), numErs = as.numeric(tt_intron))
intronTab <- intronTab[order(intronTab$numErs, decreasing=TRUE), ]
intronTab <- intronTab[- which(intronTab$gene == ''), ]
rownames(intronTab) <- NULL
dim(intronTab)
head(intronTab, n = 100)


## Annotate regions
geneRegions_intron <- ensGene[match(intronTab$gene[top], ensGene$Symbol)]
annotatedGeneRegions_intron <- annotateRegions(regions = geneRegions_intron,
	genomicState = gs, minoverlap = 1)

## Find nearest annotation with bumphunter::matchGenes()
nearestAnnotation_intron <- matchGenes(x = geneRegions_intron, subject = genes)
nearestAnnotation_intron$name = intronTab$gene[top]

## Get the region coverage
geneRegionCov_intron <- getRegionCoverage(fullCov=fullCov,
    regions=geneRegions_intron,
	targetSize = 4e+07, totalMapped = pd2$totalMapped)
geneRegionCovMeans_intron = lapply(geneRegionCov_intron, function(x) {
	cat(".")
	sapply(tIndexes, function(ii) rowMeans(x[,ii]))
})

pdf('plots/GTEX_topERs_intron.pdf', h = 5, w = 7)
plotRegionCoverage(regions = geneRegions_intron, 
	regionCoverage = geneRegionCovMeans_intron,
	groupInfo = factor(names(tIndexes), levels = c('Liver', 'Heart', 
        'Testis')), colors = brewer.pal(3, 'Set1'), 
	nearestAnnotation = nearestAnnotation_intron,
	annotatedRegions = annotatedGeneRegions_intron,
	ask = FALSE, verbose = FALSE, txdb = TranscriptDb)
dev.off()


### Make region level plot for plots/conditional_intronic_ERs_subset.pdf
intronERs <- intronRegions[match(rownames(outStatsExonSig), rownames(intronMat))[c(2, 22, 25)]]
width(intronERs)

## Find nearest annotation
nearestAnnotation_intronER <- matchGenes(x = intronERs, subject = genes)
nearestAnnotation_intronER$name <- outStatsExonSig$intronSym[c(2, 22, 25)]

## Resize to a window size
intronERs <- resize(intronERs, width(intronERs) + 2 * c(1000, 2500, 1e4),
    fix = 'center')
width(intronERs)

## Annotate windows (gets gene info in window)
annotated_intronER <- annotateRegions(regions = intronERs, genomicState = gs,
    minoverlap = 1)

## Get coverage
regionCov_intronER <- getRegionCoverage(fullCov = fullCov, verbose = FALSE,
    regions = intronERs, targetSize = 4e7, totalMapped = pd2$totalMapped)
regionCovMeans_intronER <- lapply(regionCov_intronER , function(x) {
	cat(".")
	sapply(tIndexes, function(ii) rowMeans(x[,ii]))
})

## Make plots
pdf('plots/conditional_intronic_ERs_subset_regions.pdf', h = 5, w = 7)
plotRegionCoverage(regions = intronERs, 
	regionCoverage = regionCovMeans_intronER,
	groupInfo = factor(names(tIndexes), levels = c('Liver', 'Heart', 
        'Testis')), colors = brewer.pal(3, 'Set1'), 
	nearestAnnotation = nearestAnnotation_intronER,
	annotatedRegions = annotated_intronER,
	ask = FALSE, verbose = FALSE, txdb = TranscriptDb)
dev.off()


## Code for figure 1

## Identify 500kb window to use
tiles <- tileGenome(seqlengths(regions), tilewidth = 5e5)
ov <- findOverlaps(tiles, regions)
widths <- width(regions)
tile_width <- tapply(subjectHits(ov), queryHits(ov), function(x) {
    sum(widths[x]) })
tile <- tiles[[as.integer(names(tile_width)[which.max(tile_width)])]]
tileRegions <- regions[countOverlaps(regions, tile, minoverlap = 1) > 0]
stopifnot(length(tileRegions) > 0)

## Annotate regions
annotatedTile <- annotateRegions(regions = tile,
	genomicState = gs, minoverlap = 1)
tileAnnotation <- matchGenes(x = tile, subject = genes)

## Get the region coverage
tileRegionCov <- getRegionCoverage(fullCov = fullCov, regions = tile,
	targetSize = 4e+07, totalMapped = pd2$totalMapped, verbose = FALSE)
tileRegionCovMeans = lapply(tileRegionCov, function(x) {
	cat(".")
	sapply(tIndexes, function(ii) rowMeans(x[,ii]))
})

## Panel 1: mean by group
pdf('plots/GTEX_500kb_window_panel1.pdf', h = 5, w = 7)
plotRegionCoverage(regions = tile, 
	regionCoverage = tileRegionCovMeans,
	groupInfo=factor(names(tIndexes), levels = c('Liver', 'Heart', 
        'Testis')), colors = brewer.pal(3, 'Set1'), 
	nearestAnnotation = tileAnnotation,
	annotatedRegions = annotatedTile,
	ask=FALSE,	verbose=FALSE, 
	txdb = TranscriptDb)
dev.off()

## Get the overall mean
tileMean <- rowMeans(tileRegionCov[[1]])

## Panel 2: overall mean
pdf('plots/GTEX_500kb_window_panel2.pdf', h = 5, w = 7)
scalefac <- 32
y <- log2(tileMean + scalefac)
x <- start(tile):end(tile)
layout(matrix(rep(1:3, c(8, 1, 3)), ncol = 1))
par(mar = c(0, 4.5, 0.25, 1.1), oma = c(0, 0, 2, 0))
plot(x, y, lty = 1, col = 'black', type = 'l', yaxt = 'n', ylab = '', xlab = '', xaxt = 'n', cex.lab = 1.7)
m <- ceiling(max(y))
y.labs <- seq(from = 0, to = log2(2^m - scalefac), by = 1)
axis(2, at = log2(scalefac + c(0, 2^y.labs)), labels = c(0, 
    2^y.labs), cex.axis = 1.5)
mtext('Mean coverage', side = 2, line = 2.5, cex = 1.3)
dev.off()

## Panel 3: venn diagram
tileAnno <- annotateRegions(tileRegions, gs)

pdf(file = 'plots/GTEX_500kb_window_panel3.pdf')
vennRegions(tileAnno, main = 'Expressed regions by GRCh38.p5', counts.col = 'blue')
dev.off()

## Panel 5: zoom in
zoom <- GRanges(seqnames = seqnames(tile), ranges = IRanges(start = 32000000 - 21500, width = 3300))

## Annotate regions
annotatedZoom <- annotateRegions(regions = zoom,
	genomicState = gs, minoverlap = 1)
zoomAnnotation <- matchGenes(x = zoom, subject = genes)

## Find symbol
zoomAnnotation$name <- ensGene$Symbol[ countOverlaps(ensGene, zoom, ignore.strand = TRUE) > 0 ]

## Get the region coverage
zoomRegionCov <- getRegionCoverage(fullCov = fullCov, regions = zoom,
	targetSize = 4e+07, totalMapped = pd2$totalMapped, verbose = FALSE)
zoomRegionCovMeans = lapply(zoomRegionCov, function(x) {
	cat(".")
	sapply(tIndexes, function(ii) rowMeans(x[,ii]))
})

## Panel 1: mean by group
pdf('plots/GTEX_500kb_window_panel5.pdf', h = 5, w = 7)
plotRegionCoverage(regions = zoom, 
	regionCoverage = zoomRegionCovMeans,
	groupInfo=factor(names(tIndexes), levels = c('Liver', 'Heart', 
        'Testis')), colors = brewer.pal(3, 'Set1'), 
	nearestAnnotation = zoomAnnotation,
	annotatedRegions = annotatedZoom,
	ask=FALSE,	verbose=FALSE, 
	txdb = TranscriptDb)
dev.off()


## Reproducibility info
Sys.time()
proc.time()
options(width = 120)
session_info()

