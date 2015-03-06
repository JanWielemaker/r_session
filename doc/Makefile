################################################################
# SWI-Prolog `R' package
# Author:    Nicos Angelopoulos
################################################################

.SUFFIXES: .tex .doc .pl

PUBLICPL=swipl
SWIPL_SRC=$(HOME)/src/pl-devel
PLTOTEX=$(PUBLICPL) -q -s pltotex.pl -g pltotex --
RUNTEX=env TEXINPUTS=$(SWIPL_SRC)/packages/pldoc $(SWIPL_SRC)/man/runtex
DOCTOTEX=$(SWIPL_SRC)/man/doc2tex
DOC=r_session
TEX=$(DOC).tex
DVI=$(DOC).dvi
PDF=$(DOC).pdf
HTML=$(DOC).html

################################################################
# Documentation
################################################################

doc:		$(PDF) $(HTML)
pdf:		$(PDF)
html:		$(HTML)

SUBTEX=		rdoc.tex

$(HTML):	$(TEX)
		latex2html $(DOC)

$(PDF):		$(TEX) $(SUBTEX)
		$(RUNTEX) --pdf $(DOC)

$(TEX):		$(DOCTOTEX)

rdoc.tex:	../prolog/r_session.pl
		$(PLTOTEX) --out=rdoc $<
.pl.tex:
		$(PLTOTEX) $*.pl
.doc.tex:
		$(DOCTOTEX) $*.doc > $*.tex

################################################################
# Clean
################################################################

clean:
		rm -f $(TEX) $(SUBTEX) *~
		$(RUNTEX) --clean $(DOC)
