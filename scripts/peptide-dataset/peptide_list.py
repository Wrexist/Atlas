"""
Master list of ~200 peptides for Atlas v1.
Organized loosely by category — the LLM will auto-classify into your 6 app categories.
Each entry: (common_name, abbreviation_hint, pubchem_search_term)
pubchem_search_term is used to query PubChem; leave as common name if unsure.
"""

PEPTIDES = [
    # ═══ GROWTH / GH-RELATED ═══
    ("BPC-157", "BPC-157", "BPC 157"),
    ("TB-500 (Thymosin Beta-4 Fragment)", "TB-500", "TB-500"),
    ("Thymosin Beta-4", "TB4", "Thymosin beta 4"),
    ("IGF-1 LR3", "IGF-1 LR3", "IGF-1 LR3"),
    ("IGF-1 DES", "IGF-1 DES", "IGF-1 DES"),
    ("CJC-1295 with DAC", "CJC-1295 DAC", "CJC-1295"),
    ("CJC-1295 without DAC (Mod GRF 1-29)", "Mod GRF 1-29", "CJC-1295"),
    ("Ipamorelin", "Ipamorelin", "Ipamorelin"),
    ("GHRP-2", "GHRP-2", "GHRP-2"),
    ("GHRP-6", "GHRP-6", "GHRP-6"),
    ("Hexarelin", "Hexarelin", "Hexarelin"),
    ("Sermorelin", "Sermorelin", "Sermorelin"),
    ("Tesamorelin", "Tesamorelin", "Tesamorelin"),
    ("MK-677 (Ibutamoren)", "MK-677", "Ibutamoren"),
    ("HGH Fragment 176-191", "AOD-9604", "AOD9604"),
    ("MGF (Mechano Growth Factor)", "MGF", "Mechano growth factor"),
    ("PEG-MGF", "PEG-MGF", "PEG-MGF"),
    ("Follistatin 344", "FST-344", "Follistatin 344"),
    ("Follistatin 315", "FST-315", "Follistatin 315"),
    ("GHK", "GHK", "GHK tripeptide"),
    ("GHK-Cu", "GHK-Cu", "GHK-Cu"),

    # ═══ HEALING / RECOVERY ═══
    ("KPV", "KPV", "KPV tripeptide"),
    ("LL-37", "LL-37", "LL-37 cathelicidin"),
    ("Pentadeca Arginate", "PDA", "Pentadeca Arginate"),
    ("VIP (Vasoactive Intestinal Peptide)", "VIP", "Vasoactive intestinal peptide"),
    ("Oxytocin", "Oxytocin", "Oxytocin"),
    ("Glutathione", "GSH", "Glutathione"),
    ("NAD+", "NAD+", "Nicotinamide adenine dinucleotide"),
    ("ARA-290", "ARA-290", "ARA-290 Cibinetide"),
    ("DSIP (Delta Sleep Inducing Peptide)", "DSIP", "Delta sleep inducing peptide"),
    ("Larazotide", "Larazotide", "Larazotide acetate"),
    ("Liraglutide", "Liraglutide", "Liraglutide"),
    ("Thymulin", "Thymulin", "Thymulin"),
    ("Syn-Ake", "Syn-Ake", "Syn-Ake peptide"),
    ("Matrixyl", "Matrixyl", "Palmitoyl pentapeptide-4"),

    # ═══ COGNITIVE / NOOTROPIC ═══
    ("Semax", "Semax", "Semax"),
    ("N-Acetyl Semax", "NA-Semax", "N-Acetyl Semax"),
    ("N-Acetyl Semax Amidate", "NASA", "N-Acetyl Semax Amidate"),
    ("Selank", "Selank", "Selank"),
    ("N-Acetyl Selank", "NA-Selank", "N-Acetyl Selank"),
    ("Cerebrolysin", "Cerebrolysin", "Cerebrolysin"),
    ("FGL (FG Loop Peptide)", "FGL", "FGL peptide"),
    ("Dihexa", "Dihexa", "Dihexa"),
    ("P21 (P021)", "P21", "P021 peptide"),
    ("PE-22-28", "PE-22-28", "PE-22-28"),
    ("Noopept", "Noopept", "Noopept"),
    ("Melanotan I", "MT-I", "Melanotan 1"),
    ("PT-141 (Bremelanotide)", "PT-141", "Bremelanotide"),

    # ═══ ANTI-AGING / LONGEVITY ═══
    ("Epitalon (Epithalon)", "Epitalon", "Epitalon"),
    ("Humanin", "Humanin", "Humanin peptide"),
    ("MOTS-c", "MOTS-c", "MOTS-c"),
    ("SS-31 (Elamipretide)", "SS-31", "Elamipretide"),
    ("FOXO4-DRI", "FOXO4-DRI", "FOXO4-DRI"),
    ("Pinealon", "Pinealon", "Pinealon"),
    ("Vesugen", "Vesugen", "Vesugen"),
    ("Khavinson peptide bioregulators", "Bioregulators", "Khavinson peptide"),
    ("Prostamax", "Prostamax", "Prostamax"),
    ("Testagen", "Testagen", "Testagen"),
    ("Cartalax", "Cartalax", "Cartalax"),
    ("Bonothyrk", "Bonothyrk", "Bonothyrk"),
    ("Livagen", "Livagen", "Livagen"),

    # ═══ IMMUNE ═══
    ("Thymosin Alpha-1", "TA1", "Thymosin alpha 1"),
    ("Thymogen", "Thymogen", "Thymogen"),
    ("Thymalin", "Thymalin", "Thymalin"),
    ("RG-Cys", "RG-Cys", "RG-Cys peptide"),
    ("Transfer Factor", "TF", "Transfer factor"),

    # ═══ METABOLIC / FAT LOSS / GLP ═══
    ("Semaglutide", "Semaglutide", "Semaglutide"),
    ("Tirzepatide", "Tirzepatide", "Tirzepatide"),
    ("Retatrutide", "Retatrutide", "Retatrutide"),
    ("Cagrilintide", "Cagrilintide", "Cagrilintide"),
    ("Dulaglutide", "Dulaglutide", "Dulaglutide"),
    ("Exenatide", "Exenatide", "Exenatide"),
    ("Lixisenatide", "Lixisenatide", "Lixisenatide"),
    ("Albiglutide", "Albiglutide", "Albiglutide"),
    ("Survodutide", "Survodutide", "Survodutide"),
    ("Orforglipron", "Orforglipron", "Orforglipron"),
    ("5-Amino-1MQ", "5-Amino-1MQ", "5-Amino-1MQ"),
    ("SLU-PP-332", "SLU-PP-332", "SLU-PP-332"),
    ("Amlexanox", "Amlexanox", "Amlexanox"),

    # ═══ PERFORMANCE / MUSCLE ═══
    ("Myostatin Inhibitor (ACE-031)", "ACE-031", "ACE-031"),
    ("ACVR2B (YK-11)", "ACVR2B", "ACVR2B"),
    ("MK-0773", "MK-0773", "MK-0773"),
    ("Adipotide (FTPP)", "Adipotide", "Adipotide"),
    ("Tesofensine", "Tesofensine", "Tesofensine"),

    # ═══ SKIN / HAIR / COSMETIC ═══
    ("Melanotan II", "MT-II", "Melanotan 2"),
    ("Copper Peptides (GHK-Cu variants)", "Cu-Peptides", "Copper tripeptide"),
    ("Argireline (Acetyl Hexapeptide-3)", "Argireline", "Acetyl hexapeptide-3"),
    ("SNAP-8", "SNAP-8", "Acetyl octapeptide-3"),
    ("Leuphasyl", "Leuphasyl", "Pentapeptide-18"),
    ("Vialox", "Vialox", "Pentapeptide-3"),
    ("Biopeptide EL", "Biopeptide EL", "Palmitoyl oligopeptide"),
    ("Biopeptide CL", "Biopeptide CL", "Palmitoyl tripeptide-1"),
    ("Eyeseryl", "Eyeseryl", "Acetyl tetrapeptide-5"),
    ("Decorinyl", "Decorinyl", "Tripeptide-10 citrulline"),
    ("Trifluoroacetyl Tripeptide-2", "TT-2", "Trifluoroacetyl tripeptide-2"),
    ("Rigin (Palmitoyl tetrapeptide-7)", "Rigin", "Palmitoyl tetrapeptide-7"),
    ("Progeline", "Progeline", "Trifluoroacetyl tripeptide-2"),
    ("Dermorphin", "Dermorphin", "Dermorphin"),

    # ═══ REGENERATIVE / JOINT ═══
    ("Humanin S14G", "HNG", "Humanin S14G"),
    ("Gonadorelin", "Gonadorelin", "Gonadorelin"),
    ("Kisspeptin-10", "KP-10", "Kisspeptin-10"),
    ("Triptorelin", "Triptorelin", "Triptorelin"),
    ("Leuprolide", "Leuprolide", "Leuprolide"),
    ("Buserelin", "Buserelin", "Buserelin"),

    # ═══ ANTIMICROBIAL / ANTI-VIRAL ═══
    ("Magainin", "Magainin", "Magainin"),
    ("Defensin", "Defensin", "Human defensin"),
    ("Lactoferrin", "Lactoferrin", "Lactoferrin"),
    ("Nisin", "Nisin", "Nisin"),
    ("Polymyxin B", "Polymyxin B", "Polymyxin B"),
    ("Gramicidin", "Gramicidin", "Gramicidin"),
    ("Colistin", "Colistin", "Colistin"),
    ("Bacitracin", "Bacitracin", "Bacitracin"),

    # ═══ HORMONAL ═══
    ("Insulin", "Insulin", "Insulin"),
    ("Glucagon", "Glucagon", "Glucagon"),
    ("Oxyntomodulin", "OXM", "Oxyntomodulin"),
    ("PYY 3-36", "PYY", "Peptide YY"),
    ("Ghrelin", "Ghrelin", "Ghrelin"),
    ("Leptin", "Leptin", "Leptin"),
    ("Calcitonin", "Calcitonin", "Calcitonin"),
    ("Parathyroid Hormone (1-34)", "PTH 1-34", "Teriparatide"),
    ("Vasopressin", "AVP", "Vasopressin"),
    ("Desmopressin", "DDAVP", "Desmopressin"),

    # ═══ ADDITIONAL RESEARCH PEPTIDES ═══
    ("5-HT Receptor Peptides", "5-HT", "5-HT peptide"),
    ("AGRP (Agouti-related peptide)", "AGRP", "Agouti-related peptide"),
    ("Alpha-MSH", "α-MSH", "Alpha melanocyte"),
    ("Angiotensin II", "Ang II", "Angiotensin II"),
    ("Angiotensin 1-7", "Ang 1-7", "Angiotensin 1-7"),
    ("Atrial Natriuretic Peptide", "ANP", "Atrial natriuretic peptide"),
    ("BNP (Brain Natriuretic Peptide)", "BNP", "Brain natriuretic peptide"),
    ("Bradykinin", "BK", "Bradykinin"),
    ("Bombesin", "Bombesin", "Bombesin"),
    ("Cecropin", "Cecropin", "Cecropin"),
    ("Cholecystokinin (CCK-8)", "CCK-8", "Cholecystokinin 8"),
    ("Corticotropin Releasing Hormone", "CRH", "Corticotropin releasing hormone"),
    ("Dynorphin A", "Dynorphin", "Dynorphin A"),
    ("Endomorphin-1", "EM-1", "Endomorphin 1"),
    ("Endomorphin-2", "EM-2", "Endomorphin 2"),
    ("Endothelin-1", "ET-1", "Endothelin 1"),
    ("Enkephalin", "Enk", "Methionine enkephalin"),
    ("Galanin", "Galanin", "Galanin"),
    ("Gastrin", "Gastrin", "Gastrin"),
    ("GLP-2 (Teduglutide)", "GLP-2", "Teduglutide"),
    ("Guanylin", "Guanylin", "Guanylin"),
    ("Hepcidin", "Hepcidin", "Hepcidin"),
    ("Melanin Concentrating Hormone", "MCH", "Melanin concentrating hormone"),
    ("Melanocortin", "MC", "Melanocortin"),
    ("Motilin", "Motilin", "Motilin"),
    ("Neuropeptide Y", "NPY", "Neuropeptide Y"),
    ("Neurotensin", "NT", "Neurotensin"),
    ("Orexin A", "OX-A", "Orexin A"),
    ("Orexin B", "OX-B", "Orexin B"),
    ("Oxytocin Fragment", "OT-Frag", "Oxytocin fragment"),
    ("Relaxin", "Relaxin", "Relaxin"),
    ("Secretin", "Secretin", "Secretin"),
    ("Somatostatin", "SST", "Somatostatin"),
    ("Octreotide", "Octreotide", "Octreotide"),
    ("Lanreotide", "Lanreotide", "Lanreotide"),
    ("Pasireotide", "Pasireotide", "Pasireotide"),
    ("Substance P", "SP", "Substance P"),
    ("Thyrotropin Releasing Hormone", "TRH", "Thyrotropin releasing hormone"),
    ("Urocortin", "Urocortin", "Urocortin"),
    ("Urotensin II", "U-II", "Urotensin II"),

    # ═══ RESEARCH / EXPERIMENTAL ═══
    ("SS-20", "SS-20", "SS-20 peptide"),
    ("Gonadotropin (HCG)", "HCG", "Human chorionic gonadotropin"),
    ("Menotropin (HMG)", "HMG", "Human menopausal gonadotropin"),
    ("FSH", "FSH", "Follicle stimulating hormone"),
    ("LH", "LH", "Luteinizing hormone"),
    ("TSH", "TSH", "Thyroid stimulating hormone"),
    ("ACTH", "ACTH", "Adrenocorticotropic hormone"),
    ("Cosyntropin", "Cosyntropin", "Cosyntropin"),
    ("Glucagon-like peptide 1", "GLP-1", "Glucagon like peptide 1"),
    ("GIP (Glucose-dependent Insulinotropic Peptide)", "GIP", "Gastric inhibitory polypeptide"),
    ("Amylin", "Amylin", "Amylin"),
    ("Pramlintide", "Pramlintide", "Pramlintide"),

    # ═══ ADDITIONAL NOOTROPICS / NEURO ═══
    ("Cortexin", "Cortexin", "Cortexin"),
    ("Celtypan", "Celtypan", "Celtypan"),
    ("Peptide R", "PR", "Peptide R"),
    ("Davunetide (NAP)", "NAP", "Davunetide"),
    ("SNK-411", "SNK-411", "SNK-411"),

    # ═══ CARDIAC / VASCULAR ═══
    ("Cortagen", "Cortagen", "Cortagen"),
    ("Bronchogen", "Bronchogen", "Bronchogen"),
    ("Chonluten", "Chonluten", "Chonluten"),
    ("Cardiogen", "Cardiogen", "Cardiogen"),
    ("Crostagen", "Crostagen", "Crostagen"),
    ("Ovagen", "Ovagen", "Ovagen"),
    ("Pancragen", "Pancragen", "Pancragen"),
    ("Renagen", "Renagen", "Renagen"),
    ("Vladonix", "Vladonix", "Vladonix"),
    ("Ventfort", "Ventfort", "Ventfort"),

    # ═══ ADDITIONAL GLP/OBESITY PIPELINE ═══
    ("MariTide", "MariTide", "Maridebart cafraglutide"),
    ("Danuglipron", "Danuglipron", "Danuglipron"),
    ("Ecnoglutide", "Ecnoglutide", "Ecnoglutide"),
    ("Mazdutide", "Mazdutide", "Mazdutide"),
    ("Efinopegdutide", "Efinopegdutide", "Efinopegdutide"),
    ("Pemvidutide", "Pemvidutide", "Pemvidutide"),
    ("VK2735", "VK2735", "VK2735"),
    ("LY3841136", "LY3841136", "LY3841136"),

    # ═══ SPECIALTY / NICHE ═══
    ("Apelin-13", "Apelin-13", "Apelin 13"),
    ("Elabela", "Elabela", "Elabela peptide"),
    ("Adropin", "Adropin", "Adropin"),
    ("Betatrophin", "Betatrophin", "Betatrophin"),
    ("Irisin", "Irisin", "Irisin"),
    ("Spexin", "Spexin", "Spexin"),
    ("Nesfatin-1", "Nesfatin-1", "Nesfatin 1"),
    ("Phoenixin", "Phoenixin", "Phoenixin"),
    ("Asprosin", "Asprosin", "Asprosin"),
    ("FGF-21", "FGF-21", "Fibroblast growth factor 21"),
    ("Klotho", "Klotho", "Klotho protein"),
    ("Sirtuin Activating Peptides", "SAP", "Sirtuin activating peptide"),
]

# Deduplicate by abbreviation while preserving order
_seen = set()
PEPTIDES_DEDUPED = []
for entry in PEPTIDES:
    key = entry[1].lower()
    if key not in _seen:
        _seen.add(key)
        PEPTIDES_DEDUPED.append(entry)

if __name__ == "__main__":
    print(f"Total peptides: {len(PEPTIDES_DEDUPED)}")
