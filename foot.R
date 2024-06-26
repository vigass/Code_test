rm(list = ls())
setwd("D:\\Test\\knee arthritis\\GSE55457")

# Step1 数据下载 -------------------------------------------------------------
library(GEOquery)
# if (!require("BiocManager", quietly = TRUE))
# install.packages("BiocManager")
# 
# BiocManager::install("GEOquery")
options(timeout = 300)
gse = "GSE55457"
eSet <- getGEO(gse,
               destdir = '.',
               getGPL = F)
# library(AnnoProbe)#install.packages('AnnoProbe')
# #devtools::install_git("https://gitee.com/jmzeng/GEOmirror")
# eSet <- AnnoProbe::geoChina(gse='GSE10667', mirror = 'tencent', destdir = '.')

exp <- exprs(eSet[[1]])
exp[1:4,1:4]
pd <- pData(eSet[[1]])
gpl <- eSet[[1]]@annotation
p = identical(rownames(pd),colnames(exp))
save(gse,exp,pd,gpl,file = "step2_output.Rdata")

# Step2 数据预处理 -------------------------------------------------------------
rm(list = ls())
load("step2_output.Rdata")
library(stringr)
library(dplyr)
table(colnames(exp))
View(pd)
options(timeout = 300)
if(T){
  a = getGEO(gpl,destdir = ".")
  b = a@dataTable@table
  colnames(b)
  ids2 = b[,c("ID","Gene Symbol")]
  colnames(ids2) = c("probe_id","symbol")
  ids2 = ids2[ids2$symbol!="" & !str_detect(ids2$symbol,"///"),]
}
# library(biomaRt)
# ensembl <- useMart("ensembl", dataset = "hsapiens_gene_ensembl")
# 
# b1 <- b %>%
#   filter(GB_ACC != "")
# 
# refseq_id <- b1$GB_ACC
# genes <- getBM(attributes = c("refseq_mrna", "external_gene_name"),
#                filters = "refseq_mrna",
#                values = refseq_id,
#                mart = ensembl)
# b2 <- merge(b1,genes, by.x = 'GB_ACC', by.y = 'refseq_mrna')
# colnames(b2)[9] <-'genes'
# b3 <- b2[!is.na(b2$genes) & b2$genes !='',]
# b4 <- b3[,c('ID','genes')]
exp1 <- data.frame(exp)
exp1 <- mutate(exp1, probe_id = rownames(exp))
exp1 <- merge(x = exp1, y = ids2, by = "probe_id")
exp1 <- exp1[!duplicated(exp1$symbol),]
row.names(exp1) <- exp1$symbol
exp1 <- exp1[,-1]
exp1 <- exp1[,-ncol(exp1)]

# exp1 <- mutate(exp1, id = rownames(exp))
# exp1 <- merge(x = exp1, y = b4, by.x = "id", by.y = 'ID')
# exp1 <- exp1[!duplicated(exp1$genes),]
# 
# row.names(exp1) <- exp1$genes
# exp1 <- exp1[,-1]
# exp1 <- exp1[,-ncol(exp1)]
# View(exp1)
save(exp1,pd, file = "step3_output.Rdata")

# Step3 数据分类 --------------------------------------------------------------
rm(list = ls())
load("step3_output.Rdata")
# pd$group <- ifelse(pd$`bmi (kg/m2):ch1` <= 29.9, 'Overweight', 'Obese')
# filtered_pd_ <- pd %>%
#   filter(pd$characteristics_ch1 %in% c('organ: Bone','organ: Breast'))
# filtered_pd$characteristics_ch1 <- factor(filtered_pd$characteristics_ch1, levels = c('organ: Bone','organ: Breast'))
# filtered_pd <- filtered_pd[order(filtered_pd$characteristics_ch1), ]
pd$group <- NA
pd$group <- ifelse(pd$`clinical status:ch1` == 'normal control', 'Normal',
                   ifelse(pd$`clinical status:ch1` == 'rheumatoid arthritis', 'RA', 'OA'))
filter_pd <- pd %>%
  filter(group %in% c('Normal', 'OA'))

filter_pd$group <- factor(filter_pd$group,levels = c('Normal','OA'))
filter_pd <- filter_pd[order(filter_pd$group), ]
group_list <- filter_pd$group
match_positions <- match(filter_pd$geo_accession, colnames(exp1))
exp2 <- exp1[, match_positions]

save(group_list,exp2,pd,filter_pd, file = "step4_output.Rdata")


# Step4 PCA分析 -------------------------------------------------------------
rm(list = ls())
load("step4_output.Rdata")
library(FactoMineR)
library(factoextra)
library(tidyverse)
library(ggsci)
table(pd$group)
cors <- pal_lancet()(5)
dat=as.data.frame(t(exp2))
dat.pca <- PCA(dat, graph = FALSE)

pca_plot <- fviz_pca_ind(dat.pca,
                         geom.ind = "point",
                         col.ind = group_list,
                         palette = cors,#####色彩颜色根据分组个数决定
                         addEllipses = TRUE,
                         legend.title = "Groups")
print(pca_plot)
save(pca_plot,file = 'pca.Rdata')


# Step5 差异分析 --------------------------------------------------------------
#差异分析
rm(list = ls())
load("step4_output.Rdata")

library(clusterProfiler)
library(stringr)
geneset <- read.gmt("OXIDATIVE_STRESS.v2023.2.Hs.gmt")

x <- data.frame(list(geneset$gene))
colnames(x) <- "genes"
x <- unique(x)
exp2 <- exp2[rownames(exp2) %in% x$genes, ]

library(limma)
design=model.matrix(~group_list)
fit=lmFit(data.frame(exp2), design)
fit=eBayes(fit)
deg=topTable(fit, coef=2, number = Inf)
deg <- mutate(deg,probe_id=rownames(deg))

logFC_t= 1.5
change=ifelse(deg$P.Value>0.05,'Stable',
              ifelse(abs(deg$logFC) < logFC_t,'Stable',
                     ifelse(deg$logFC >= logFC_t,'Up','Down') ))
deg <- mutate(deg, change)
table(deg$change)
write.csv(data.frame(deg),'degs.csv')
# library(ggsci)
# cors <- pal_lancet()(3)
# show_col(cors)
library(ggplot2)
ggplot(deg,aes(logFC,
               -log10(P.Value)))+
  geom_point(size = 3.5, 
             alpha = 0.8, 
             aes(color = change),
             show.legend = T)+
  scale_color_manual(values = c('#35d315','gray','#e64c46'))+
  ylim(0, 10)+
  xlim(-3500, 3500)+
  labs(x = 'LogFC',y = '-Log10(P.Value)')+
  geom_hline(yintercept = -log10(0.05),
             linetype = 2,
             color = 'black',lwd = 0.8)+
  geom_vline(xintercept = c(-1.5, 1.5),
             linetype = 2, 
             color = 'black', lwd = 0.8)+
  theme_bw()+
  theme(panel.grid.major = element_blank(),
        panel.grid.minor = element_blank())

deg_gene <- deg$probe_id[deg$change %in% c('Up','Down')]
# write.csv(data.frame(deg_gene),'deg_gene.csv')
exp3 <- exp2[rownames(exp2) %in% deg_gene, ]

table(deg$change)
cg=names(tail(sort(apply(exp3,1,sd)),73))#SD,top50
n=exp3[cg,]
annotation_col=data.frame(group=group_list)
rownames(annotation_col) = colnames(n)

library(pheatmap)
heatmap_plot <- pheatmap(n,
                         show_colnames=F,
                         show_rownames = T,
                         annotation_col = annotation_col,
                         scale = "row",
                         cluster_cols = FALSE)
save(deg,heatmap_plot,file = 'volcano_heatmap.Rdata')
save(deg,deg_gene,file = 'enrich_analysis.Rdata')
save(exp2,exp3,filter_pd,group_list,deg, file = "step5_output.Rdata")

# Step6 富集分析 --------------------------------------------------------------
#enrichment analysis
rm(list = ls())
load('enrich_analysis.Rdata')
library(org.Hs.eg.db)
library(clusterProfiler)
library(org.Hs.eg.db)
#测试
test_genes <- c("CETN2", "FZD4", "BBS1", "TSGA10", "SLC38A3", "PAXIP1")
ego_test <- enrichGO(gene = test_genes,
                     OrgDb = org.Hs.eg.db,
                     keyType = "SYMBOL",
                     ont = "BP",
                     pAdjustMethod = "BH",
                     qvalueCutoff = 0.05)

print(ego_test)
gene <- rownames(deg)
#GO富集
#BP模块
GO_BP<-enrichGO( gene = gene,
                 OrgDb = org.Hs.eg.db,
                 keyType = "SYMBOL",
                 ont = "BP",
                 pvalueCutoff = 0.05,
                 pAdjustMethod = "BH",
                 qvalueCutoff = 0.05,
                 minGSSize = 10,
                 maxGSSize = 500,
                 readable = T)
#CC模块
GO_CC<-enrichGO( gene = gene,
                 OrgDb = org.Hs.eg.db,
                 keyType = "SYMBOL",
                 ont = "CC",
                 pvalueCutoff = 0.05,
                 pAdjustMethod = "BH",
                 qvalueCutoff = 0.05,
                 minGSSize = 10,
                 maxGSSize = 500,
                 readable = T)
#MF模块
GO_MF<-enrichGO( gene = gene,
                 OrgDb = org.Hs.eg.db,
                 keyType = "SYMBOL",
                 ont = "MF",
                 pvalueCutoff = 0.05,
                 pAdjustMethod = "BH",
                 qvalueCutoff = 0.05,
                 minGSSize = 10,
                 maxGSSize = 500,
                 readable = T)
ego_result_BP <- as.data.frame(GO_BP)
ego_result_CC <- as.data.frame(GO_CC)
ego_result_MF <- as.data.frame(GO_MF)
# ego <- rbind(ego_result_BP,ego_result_CC,ego_result_MF)#或者这样也能得到ego_ALL一样的结果
# ego_ALL <- as.data.frame(ego)
# write.csv(ego_ALL,file = "ego_ALL.csv",row.names = T)
write.csv(ego_result_BP,file = "ego_result_BP.csv",row.names = T)
write.csv(ego_result_CC,file = "ego_result_CC.csv",row.names = T)
write.csv(ego_result_MF,file = "ego_result_MF.csv",row.names = T)

display_number = c(10, 10, 10)#这三个数字分别代表选取的BP、CC、MF的通路条数，这个自己设置就行了
ego_result_BP <- as.data.frame(GO_BP)[1:display_number[1], ]
ego_result_CC <- as.data.frame(GO_CC)[1:display_number[2], ]
ego_result_MF <- as.data.frame(GO_MF)[1:display_number[3], ]

go_enrich_df <- data.frame(
  ID=c(ego_result_BP$ID, ego_result_CC$ID, ego_result_MF$ID),                        
  Description=c(ego_result_BP$Description,ego_result_CC$Description,ego_result_MF$Description),
  GeneNumber=c(ego_result_BP$Count, ego_result_CC$Count, ego_result_MF$Count),
  type=factor(c(rep("biological process", display_number[1]), 
                rep("cellular component", display_number[2]),
                rep("molecular function", display_number[3])), 
              levels=c("biological process", "cellular component","molecular function" )))
for(i in 1:nrow(go_enrich_df)){
  description_splite=strsplit(go_enrich_df$Description[i],split = " ")
  description_collapse=paste(description_splite[[1]][1:5],collapse = " ") #这里的5就是指5个单词的意思，可以自己更改
  go_enrich_df$Description[i]=description_collapse
  go_enrich_df$Description=gsub(pattern = "NA","",go_enrich_df$Description)
}
library(ggplot2)
##开始绘制GO柱状图
###横着的柱状图
go_enrich_df$type_order=factor(rev(as.integer(rownames(go_enrich_df))),labels=rev(go_enrich_df$Description))
#这一步是必须的，为了让柱子按顺序显示，不至于很乱
COLS <- c("#66C3A5", "#8DA1CB", "#FD8D62")#设定颜色

ggplot(data=go_enrich_df, aes(x=type_order,y=GeneNumber, fill=type)) + #横纵轴取值
  geom_bar(stat="identity", width=0.8) + #柱状图的宽度，可以自己设置
  scale_fill_manual(values = COLS) + ###颜色
  coord_flip() + ##这一步是让柱状图横过来，不加的话柱状图是竖着的
  xlab("GO term") + 
  ylab("Gene_Number") + 
  labs(title = "Top 10 GO terms across BP, CC, and MF")+
  theme_bw()

###竖着的柱状图 
go_enrich_df$type_order=factor(rev(as.integer(rownames(go_enrich_df))),labels=rev(go_enrich_df$Description))
COLS <- c("#66C3A5", "#8DA1CB", "#FD8D62")
ggplot(data=go_enrich_df, aes(x=type_order,y=GeneNumber, fill=type)) + 
  geom_bar(stat="identity", width=0.8) + 
  scale_fill_manual(values = COLS) + 
  theme_bw() + 
  xlab("GO term") + 
  ylab("Num of Genes") + 
  labs(title = "Top 10 GO terms across BP, CC, and MF")+ 
  theme(axis.text.x=element_text(face = "bold", color="gray50",angle = 60,vjust = 1, hjust = 1 ))
#angle是坐标轴字体倾斜的角度，可以自己设置

#KEGG富集
library(AnnotationDbi)
library(org.Hs.eg.db)
library(clusterProfiler)
# gene <- deg_genes$genes

# 确保'genes'是包含基因符号的字符向量
gene_mapping <- AnnotationDbi::select(org.Hs.eg.db, 
                                      keys = gene, 
                                      keytype = "SYMBOL", 
                                      columns = "ENTREZID")

KEGG <- enrichKEGG(gene         = gene_mapping$ENTREZID,
                   organism     = 'hsa', 
                   keyType      = 'kegg', 
                   pAdjustMethod = "BH", 
                   qvalueCutoff = 0.05)
print(KEGG)
write.csv(KEGG,'kegg.csv',row.names = TRUE)
#画图1
#柱状图
barplot(KEGG,showCategory = 10,title = 'KEGG Pathway')
#点状图
dotplot(KEGG)

#画图2
kk <- KEGG
###柱状图
hh <- as.data.frame(kk)
rownames(hh) <- 1:nrow(hh)
hh$order=factor(rev(as.integer(rownames(hh))),labels = rev(hh$Description))
ggplot(hh,aes(y=order,x=Count,fill=p.adjust))+
  geom_bar(stat = "identity",width=0.7)+####柱子宽度
  #coord_flip()+##颠倒横纵轴
  scale_fill_gradient(low = "red",high ="blue" )+#颜色自己可以换
  labs(title = "KEGG Pathways Enrichment",
       x = "Gene numbers", 
       y = "Pathways")+
  theme(axis.title.x = element_text(face = "bold",size = 16),
        axis.title.y = element_text(face = "bold",size = 16),
        legend.title = element_text(face = "bold",size = 16))+
  theme_bw()
###气泡图
hh <- as.data.frame(kk)
rownames(hh) <- 1:nrow(hh)
hh$order=factor(rev(as.integer(rownames(hh))),labels = rev(hh$Description))
ggplot(hh,aes(y=order,x=Count))+
  geom_point(aes(size=Count,color=-1*p.adjust))+# 修改点的大小
  scale_color_gradient(low="green",high = "red")+
  labs(color=expression(p.adjust,size="Count"), 
       x="Gene Number",y="Pathways",title="KEGG Pathway Enrichment")+
  theme_bw()

# Step7 WGCNA分析 -----------------------------------------------------------
#WGCNA
rm(list = ls())
load("step5_output.Rdata")

library(tidyverse)
exp_wgcna <- exp2[,colnames(exp2) %in% filter_pd$geo_accession]
samples <- filter_pd[,c("geo_accession","group")]
samples$group <- ifelse(samples$group=="OA","1","0")
rownames(samples) <- seq_len(nrow(samples))

library(WGCNA)
dataExpr <- exp_wgcna
m.mad <- apply(dataExpr, 1, mad)
dataExprVar <- dataExpr[which(m.mad > 
                                max(quantile(m.mad, probs=seq(0,1,0.25))[2],0.01)),]
dataExpr <- as.data.frame(t(dataExprVar))

gsg = goodSamplesGenes(dataExpr, verbose = 3)

if(!gsg$allOK){
  if(sum(!gsg$goodGenes)>0)
    printFlush(paste("Removing genes:",
                     paste(names(dataExpr)[!gsg$goodGenes], collapse = ",")));
  if(sum(!gsg$goodSamples)>0)
    printFlush(paste("Removing samples:",
                     paste(rownames(dataExpr)[!gsg$goodSamples], collapse = ",")));
  dataExpr = dataExpr[gsg$goodSamples, gsg$goodGenes]
}
nGenes = ncol(dataExpr)
nSamples = nrow(dataExpr)
dim(dataExpr)

sampleTree = hclust(dist(dataExpr), method = "average")
par(cex = 0.9);
par(mar = c(0,4,2,0))
plot(sampleTree, main = "Sample clustering to detect outliers", sub="", xlab="", cex.lab = 1.5,
     cex.axis = 1.5, cex.main = 2)
datExpr = as.data.frame(dataExpr)
nGenes = ncol(datExpr)
nSamples = nrow(datExpr)

plot(sampleTree, main = "Sample clustering to detect outliers", sub="", xlab="", cex.lab = 1.5, cex.axis = 1.5, cex.main = 2) +
  #想用哪里切，就把“h = 110”和“cutHeight = 110”中换成你的cutoff
  abline(h = 35000, col = "red") 
clust = cutreeStatic(sampleTree, cutHeight = 35000, minSize = 10)
keepSamples = (clust==1)
datExpr = dataExpr[keepSamples, ]
nGenes = ncol(datExpr)
nSamples = nrow(datExpr)
datExpr=as.data.frame(datExpr)
sample_to_delete <- c("GSM1337304")
samples <- samples[!samples$geo_accession %in% sample_to_delete,]

powers = c(c(1:10), seq(from = 12, to=20, by=2))

sft = pickSoftThreshold(datExpr, powerVector = powers,
                        verbose = 5 )
pdf("1Threshold.pdf",width = 9, height = 5)
par(mfrow = c(1,2))
cex1 = 0.8
plot(sft$fitIndices[,1], -sign(sft$fitIndices[,3])*sft$fitIndices[,2],
     xlab="Soft Threshold (power)",ylab="Scale Free Topology Model Fit,signed R^2",type="n",
     main = paste("Scale independence")) +
  text(sft$fitIndices[,1], -sign(sft$fitIndices[,3])*sft$fitIndices[,2],
       labels=powers,cex=cex1,col="red")+
  abline(h=0.8,col="red")
plot(sft$fitIndices[,1], sft$fitIndices[,5],
     xlab="Soft Threshold (power)",ylab="Mean Connectivity", type="n",
     main = paste("Mean connectivity")) +
  text(sft$fitIndices[,1], sft$fitIndices[,5], labels=powers, cex=cex1,col="red")
dev.off()
sft$powerEstimate
#构建网络，找出gene module
net = blockwiseModules(datExpr, power = 6,
                       TOMType = "unsigned", minModuleSize = 10,
                       reassignThreshold = 0, mergeCutHeight = 0.15,
                       numericLabels = TRUE, pamRespectsDendro = FALSE,
                       saveTOMs = TRUE,
                       #saveTOMFileBase = "MyTOM",
                       verbose = 3)

table(net$colors)
mergedColors = labels2colors(net$colors)
pdf("2module.pdf",width = 10, height = 5)
plotDendroAndColors(net$dendrograms[[1]], mergedColors[net$blockGenes[[1]]], "Module colors",
                    dendroLabels = FALSE, hang = 0.03, 
                    addGuide = TRUE, guideHang = 0.05)
dev.off()
moduleLabels = net$colors
moduleColors = labels2colors(net$colors)
MEs = net$MEs;
geneTree = net$dendrograms[[1]]

#把gene module输出到文件
text <- unique(moduleColors)
for (i  in 1:length(text)) {
  y=t(assign(paste(text[i],"expr",sep = "."),
             datExpr[moduleColors==text[i]]))
  write.csv(y,paste(text[i],"csv",sep = "."),quote = F)
}

#表型与模块的相关性
moduleLabelsAutomatic = net$colors
moduleColorsAutomatic = labels2colors(moduleLabelsAutomatic)
moduleColorsWW = moduleColorsAutomatic
MEs0 = moduleEigengenes(datExpr, moduleColorsWW)$eigengenes
MEsWW = orderMEs(MEs0)

group_list <- ifelse(samples$group == '0', 'Normal', 'OA')
design <- model.matrix(~0+factor(group_list))
colnames(design)=levels(factor(group_list))
rownames(design)=colnames(exp2)
modTraitCor = cor(MEsWW,design, use = "p")

colnames(MEsWW)
modlues=MEsWW
nSamples <- ncol(datExpr)
modTraitP = corPvalueStudent(modTraitCor, nSamples)
textMatrix = paste(signif(modTraitCor, 2), "\n(", signif(modTraitP, 1), ")", sep = "")

dim(textMatrix) = dim(modTraitCor)

pdf("3Module-trait.pdf",width = 6, height = 6)
labeledHeatmap(Matrix = modTraitCor, 
               xLabels = colnames(design), 
               yLabels = names(MEsWW), cex.lab = 0.5,  yColorWidth=0.01, 
               xColorWidth = 0.03,
               ySymbols = colnames(modlues), 
               colorLabels = FALSE, colors = blueWhiteRed(50), 
               textMatrix = textMatrix, 
               setStdMargins = FALSE, cex.text = 0.5, zlim = c(-1,1),
               main = paste("Module-trait relationships"))
dev.off()

# #veen
# rm(list = ls())
# exp_cors <- read.csv('turquoise.csv',row.names = 1)
# wgcna_genes <- rownames(exp_cors)
# exp_deg <- read.csv('deg_gene.csv',row.names = 1)
# deg_genes <- exp_deg$deg_gene
# library (VennDiagram)  #install.packages("VennDiagram")
# library(openxlsx) #install.packages("openxlsx")
# library(ggsci)
# cors <- pal_aaas()(6)
# venn.diagram(x=list(wgcna_genes,deg_genes),
#              scaled = F, # 根据比例显示大小
#              alpha= 0.5, #透明度
#              lwd=1,lty=1,col=c('#3B4992FF','#EE0000FF'), #圆圈线条粗细、形状、颜色；1 实线, 2 虚线, blank无线条
#              label.col ='black' , # 数字颜色abel.col=c('#FFFFCC','#CCFFFF',......)根据不同颜色显示数值颜色
#              cex = 2, # 数字大小
#              fontface = "bold",  # 字体粗细；加粗bold
#              fill=c('#3B4992FF','#EE0000FF'), # 填充色 配色https://www.58pic.com/
#              category.names = c("WGCNA_genes", "Deg_genes") , #标签名
#              cat.dist = 0.02, # 标签距离圆圈的远近
#              cat.pos = -180, # 标签相对于圆圈的角度cat.pos = c(-10, 10, 135)
#              cat.cex = 2, #标签字体大小
#              cat.fontface = "bold",  # 标签字体加粗
#              cat.col='black' ,   #cat.col=c('#FFFFCC','#CCFFFF',.....)根据相应颜色改变标签颜色
#              cat.default.pos = "outer",  # 标签位置, outer内;text 外
#              output=TRUE,
#              filename='Veen.png',# 文件保存
#              imagetype="png",  # 类型（tiff png svg
#              resolution = 400,  # 分辨率
#              compression = "lzw"# 压缩算法
# )

# Step8 机器学习筛选基因 ----------------------------------------------------------
rm(list = ls())
load("step5_output.Rdata")
#library(randomForest)
library(glmnet)
set.seed(111)
veen <- read.csv('DEGs&MEblack.csv')
m <- veen$DEGs.MEblack[1:14]
hubgenes=m
hubgenes_expression<-exp2[match(hubgenes,rownames (exp2)),]

x=as.matrix(hubgenes_expression[,c(1:ncol(hubgenes_expression))])
samples <- filter_pd[,c("geo_accession","group")]
samples$group <- ifelse(samples$group=="Normal","0","1")


design=as.data.frame(samples)
y=data.matrix(design$group)
y <- as.factor(y)
x=t(x)
fit=glmnet(x,y,family = "binomial",maxit = 10000, nfold = 10)
plot(fit,xvar="lambda",label = TRUE)

cvfit = cv.glmnet(x,y,family="binomia",maxit = 10000, nfold = 10)
plot(cvfit)

coef=coef(fit,s = cvfit$lambda.min)
index=which(coef != 0)
actCoef=coef[index]
lassoGene=row.names(coef)[index]
geneCoef=cbind(Gene=lassoGene,Coef=actCoef)#查看模型的相关系数geneCoef
geneCoef

lassoGene <- lassoGene[-1]
actCoef<- actCoef[-1]
write.csv(geneCoef, file = 'geneCoef.csv')

###randomForest
library(randomForest)
library(caret)
set.seed(100)
ctrl <- trainControl(method = "cv", number = 10)
rf <- randomForest(y~.,  data = x , ntree = 5000 , trainControl = ctrl)
plot(rf, main = 'Random Forest', lwd = 2, ylim = c(0,1))

optionTrees = which.min(rf$err.rate[, 1])
#rf2 = randomForest(y~., data = x, ntree = optionTrees, importance = T)
rf2 = randomForest(y~., data = x, ntree = optionTrees)
importance = importance(x = rf2)
varImpPlot(rf2, main = 'Feature Importance')
rfGenes = importance[order(importance[, 'MeanDecreaseGini'], decreasing = T), ]
rfGenes = names(rfGenes[rfGenes > 0.5])
rfGenes
# write.table(rfGenes, 'random_genes.txt', sep = "\t",
#             row.names = F, col.names = F, quote = )
write.csv(rfGenes, file = 'random_genes.csv')

save(geneCoef, rfGenes, exp2, samples, file = 'machine_learn.Rdata')

#ROC验证
rm(list = ls())
load('machine_learn.Rdata')
veen <- read.csv('Lasso&RF.csv')
genes <- veen$Lasso.RandomForest[1:4]

roc_exp <- as.matrix(exp2[genes, ])
# roc_exp<-exp_ml[match(genes,rownames (exp_ml)),]
# samples$group <- ifelse(samples$group == "0", 'normal', 'tumor')
samples$group <- factor(samples$group)
library(ggsci)
cors <- pal_lancet()(6)

library(pROC)
roc_results <- list()
for (gene in genes) {
  # 提取当前基因的表达值
  predictor <- roc_exp[gene, ]
  # 计算 ROC
  roc_obj <- roc(response = samples$group, predictor = predictor)
  # 将 ROC 对象保存到列表中
  roc_results[[gene]] <- roc_obj
  # 打印 AUC 值
  cat("Gene:", gene, "AUC:", auc(roc_obj), "\n")
}
plot(roc_results[[1]], col = cors[1], lwd = 2, 
     main = "ROC Curves for Multiple Genes", 
     xlab = "False Positive Rate (1 - Specificity)", 
     ylab = "True Positive Rate (Sensitivity)", 
     ylim = c(0, 1), xlim = c(0, 1))
abline(a = 0, b = 1, lwd = 2, lty = 2, col = "red")
for (i in seq_along(roc_results)) {
  lines(roc_results[[i]], col = cors[i], lwd = 2)
}
legend("bottomright", legend = names(roc_results), col = cors, lwd = 2, bty = "n")

for (i in seq_along(roc_results)) {
  text(x = 1.0, y = 1 - 0.05 * i, 
       labels = paste(names(roc_results)[i], "AUC = ", round(auc(roc_results[[i]]), 2)), 
       col = cors[i], cex = 1.2, pos = 4)
}


# Step9 TME微环境分析 ----------------------------------------------------------
rm(list = ls())
load('step4_output.Rdata')
#免疫浸润
#CIBERSORT免疫浸润
rm(list = ls())
load("step4_output.Rdata")
library('devtools')##devtools::install_github("Moonerss/CIBERSORT")
library(CIBERSORT)
library(reader)
library(ggplot2)
library(reshape2)
library(ggpubr)
library(dplyr)
library(ggsci)
cors <- pal_lancet()(2)
data("LM22")
TME.results <- cibersort(LM22,exp2,perm = 0,QN = F)
group_list
TME_data <- as.data.frame(TME.results[,1:22])
TME_data$group <- group_list
TME_data$sample <- row.names(TME_data)
TME_New = melt(TME_data)
colnames(TME_New)=c("Group","Sample","Celltype","Composition")  #设置行名
head(TME_New)
plot_order = TME_New[TME_New$Group=="OA",] %>% 
  group_by(Celltype) %>% 
  summarise(m = median(Composition)) %>% 
  arrange(desc(m)) %>% 
  pull(Celltype)
TME_New$Celltype = factor(TME_New$Celltype,levels = plot_order)

if(T){
  mytheme <- theme(plot.title = element_text(size = 12,color="black",hjust = 0.5),
                   axis.title = element_text(size = 12,color ="black"), 
                   axis.text = element_text(size= 12,color = "black"),
                   panel.grid.minor.y = element_blank(),
                   panel.grid.minor.x = element_blank(),
                   axis.text.x = element_text(angle = 45, hjust = 1 ),
                   panel.grid=element_blank(),
                   legend.position = "top",
                   legend.text = element_text(size= 12),
                   legend.title= element_text(size= 12)
  ) }

box_TME <- ggplot(TME_New, aes(x = Celltype, y = Composition))+ 
  labs(y="Cell composition",x= NULL,title = "TME Cell composition")+  
  geom_boxplot(aes(fill = Group),position=position_dodge(0.5),width=0.6,outlier.alpha = 0)+ 
  scale_fill_manual(values = cors)+
  theme_classic() + mytheme + 
  stat_compare_means(aes(group =  Group),
                     label = "p.signif",
                     method = "wilcox.test",
                     hide.ns = T)
box_TME
ggsave("OA_TME.pdf",box_TME,height=15,width=25,unit="cm")

TME_four = as.data.frame(TME.results[,1:20])
head(TME_four,3)

#相关性分析
library(ggcorrplot)
library(corrplot)
library(seriation)#install.packages("seriation")
TME_four1 <- TME_four[,-c(10,20)]
corrmatrix <- cor(TME_four1, method = "pearson")
testRes = cor.mtest(TME_four1, conf.level = 0.95)
pdf("CIBERSORT_cor.pdf", width = 8, height = 8)
corrplot(corrmatrix, tl.col = 'black', p.mat = testRes$p,  order = 'hclust',
         insig = 'label_sig', sig.level = c(0.001, 0.01, 0.05),
         pch.cex = 0.9, pch.col = 'grey20',type = 'lower')
dev.off()
