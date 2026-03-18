-- SPDX-FileCopyrightText: Copyright (C) 2026 Ang Li Lab <angli-lab.com>
-- SPDX-License-Identifier: AGPL-3.0-or-later
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU Affero General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU Affero General Public License for more details.
--
-- You should have received a copy of the GNU Affero General Public License
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.

-- VERSION: 20260318v1

/*********************************************************************
INSTRUCTIONS

1. THIS SCRIPT WORKS ONLY FOR FUTURE TREATMENT PLANS.
2. This script uses ServiceAreaEpicId=10. If your primary Epic service area is different, update line 2250 accordingly.
3. The location mapping values on line 863 (inside TEMP TABLE: mappings used for location name) must be adjusted for different organizations.
4. Beacon is configured differently across sites. Some organizations use it for all chemotherapy therapies, while others use it only for non-oral therapies. This query depends on Beacon usage.
5. Drug and lab classifications may vary by site, so the queries may need to be adjusted.
*********************************************************************/
/*********************************************************************
TABLE OF CONTENTS

** 0. Mapping tables
-- TEMP TABLE: medication classification
-- TEMP TABLE: chemo name lookup
-- TEMP TABLE: diagnosis classification
-- TEMP TABLE: mappings used to clean race/ethnicity
-- TEMP TABLE: mappings used for location name
** 1. Cohort tables
-- TEMP TABLE: treatment plans
-- TEMP TABLE: define index date per plan
-- TEMP TABLE: final cohort table
-- TEMP TABLE: define date ranges
** 2. Demographics & Provider
-- TEMP TABLE: demographics (long)
-- TEMP TABLE: demographics (wide)
-- TEMP TABLE: provider (wide)
** 3. Diagnoses
-- TEMP TABLE: diagnoses (long)
-- TEMP TABLE: cancer (wide)
-- TEMP TABLE: metastatic ICD (wide)
-- TEMP TABLE: VTE history (wide)
-- TEMP TABLE: paralysis history (wide)
** 4. Labs
-- TEMP TABLE: labs (long)
-- TEMP TABLE: labs (wide)
** 5. Vitals
-- TEMP TABLE: vitals (long)
-- TEMP TABLE: vitals (wide)
** 6. Medications
-- TEMP TABLE: IP medications (long)
-- TEMP TABLE: OP medications (long)
-- TEMP TABLE: Reported medications (long)
-- TEMP TABLE: IP medications (wide)
-- TEMP TABLE: OP medications (wide)
-- TEMP TABLE: Reported medications (wide)
** 7. Visits and hospitalizations
-- TEMP TABLE: past/future onc/infusion visits (long)
-- TEMP TABLE: visits (wide)
-- TEMP TABLE: hospitalizations (wide)
** 8. Staging and regimen
-- TEMP TABLE: Epic staging (long)
-- TEMP TABLE: Epic staging (wide)
-- TEMP TABLE: regimen (long)
-- TEMP TABLE: regimen (wide)
** 9. Final query
*********************************************************************/


/*********************************************************************
** 0. Mapping tables
*********************************************************************/
DECLARE @sec0_start datetime2(3) = SYSDATETIME();

-- =====================================================
-- TEMP TABLE: medication classification
-- =====================================================
DROP TABLE IF EXISTS #tmp_classified_meds;
SELECT
    md."MedicationKey",
    md."Name",
    md."SimpleGenericName",
    md."GenericName",
    md."TherapeuticClass",
    md."PharmaceuticalSubclass",
    md."Route" AS "MedRoute",
    md."Strength",
    CASE
        WHEN UPPER(md."TherapeuticClass") = 'ANTICOAGULANTS'
            AND UPPER(md."PharmaceuticalSubclass") NOT IN ('ANTICOAGULANTS - CITRATE-BASED')
        THEN 1
        ELSE 0
    END AS "isAC",
    CASE
        WHEN UPPER(md."Route") IN ('ORAL', 'INJECTION', 'INTRAVENOUS')
            AND (
                UPPER(md."GenericName") LIKE '%DARALUTEMIDE%' OR UPPER(md."GenericName") LIKE '%REGORAFENIB%' OR UPPER(md."GenericName") LIKE '%CABOZANTINIB%'
                OR UPPER(md."GenericName") LIKE '%SOFOSBUVIR%' OR UPPER(md."GenericName") LIKE '%VELPATASVIR%' OR UPPER(md."GenericName") LIKE '%VOXILAPREVIR%'
            )
        THEN 1
        ELSE 0
    END AS "isContraind",
    CASE
        WHEN UPPER(md."TherapeuticClass") = 'CARDIOVASCULAR' AND UPPER(md."SimpleGenericName") LIKE '%STATIN%'
        THEN 1
        ELSE 0
    END AS "isStatin"
INTO #tmp_classified_meds
FROM "MedicationDim" md
;

CREATE NONCLUSTERED INDEX IX_tmp_classified_meds_MedKey ON #tmp_classified_meds ("MedicationKey");
CREATE NONCLUSTERED INDEX IX_tmp_classified_meds_Flags ON #tmp_classified_meds ("isAC", "isContraind", "isStatin");


-- =====================================================
-- TEMP TABLE: chemo name lookup
-- =====================================================
DROP TABLE IF EXISTS #tmp_chemo_lookup;
CREATE TABLE #tmp_chemo_lookup (
    med_name_upper  VARCHAR(300) NOT NULL PRIMARY KEY,
    "ChemoType"     VARCHAR(300) NOT NULL
);

INSERT INTO #tmp_chemo_lookup (med_name_upper, "ChemoType") VALUES
    ('ALTRETAMINE', 'chemo'),
    ('AMSACRINE', 'chemo'),
    ('ASPARAGINASE', 'chemo'),
    ('AZACITIDINE', 'chemo'),
    ('BENDAMUSTINE', 'chemo'),
    ('BLEOMYCIN', 'chemo'),
    ('BUSULFAN', 'chemo'),
    ('CABAZITAXEL', 'chemo'),
    ('CALASPARGASE', 'chemo'),
    ('CAPECITABINE', 'chemo'),
    ('CARBOPLATIN', 'chemo'),
    ('CARMUSTINE', 'chemo'),
    ('CHLORAMBUCIL', 'chemo'),
    ('CISPLATIN', 'chemo'),
    ('CLADRIBINE', 'chemo'),
    ('CLOFARABINE', 'chemo'),
    ('CYCLOPHOSPHAMIDE', 'chemo'),
    ('CYTARABINE', 'chemo'),
    ('DACARBAZINE', 'chemo'),
    ('DACTINOMYCIN', 'chemo'),
    ('DAUNORUBICIN', 'chemo'),
    ('DECITABINE', 'chemo'),
    ('DOCETAXEL', 'chemo'),
    ('DOXORUBICIN', 'chemo'),
    ('EPIRUBICIN', 'chemo'),
    ('ERIBULIN', 'chemo'),
    ('ETOPOSIDE', 'chemo'),
    ('FOTEMUSTINE', 'chemo'),
    ('FLOXURIDINE', 'chemo'),
    ('FLUDARABINE', 'chemo'),
    ('FLUOROURACIL', 'chemo'),
    ('GEMCITABINE', 'chemo'),
    ('HYDROXYUREA', 'chemo'),
    ('IDARUBICIN', 'chemo'),
    ('IFOSFAMIDE', 'chemo'),
    ('IRINOTECAN', 'chemo'),
    ('IXABEPILONE', 'chemo'),
    ('LOMUSTINE', 'chemo'),
    ('LURBINECTEDIN', 'chemo'),
    ('MECHLORETHAMINE', 'chemo'),
    ('MELPHALAN', 'chemo'),
    ('MERCAPTOPURINE', 'chemo'),
    ('METHOTREXATE', 'chemo'),
    ('MITOMYCIN', 'chemo'),
    ('MITOXANTRONE', 'chemo'),
    ('NELARABINE', 'chemo'),
    ('OMACETAXINE', 'chemo'),
    ('OXALIPLATIN', 'chemo'),
    ('PACLITAXEL', 'chemo'),
    ('PEGASPARGASE', 'chemo'),
    ('PEMETREXED', 'chemo'),
    ('PENTOSTATIN', 'chemo'),
    ('PLICAMYCIN', 'chemo'),
    ('PORFIMER', 'chemo'),
    ('PRALATREXATE', 'chemo'),
    ('PROCARBAZINE', 'chemo'),
    ('RALTITREXED', 'chemo'),
    ('STREPTOZOCIN', 'chemo'),
    ('TEGAFUR', 'chemo'),
    ('TEMOZOLOMIDE', 'chemo'),
    ('TENIPOSIDE', 'chemo'),
    ('THIOGUANINE', 'chemo'),
    ('THIOTEPA', 'chemo'),
    ('TOPOTECAN', 'chemo'),
    ('TRABECTEDIN', 'chemo'),
    ('TRIFLURIDINE', 'chemo'),
    ('TREOSULFAN', 'chemo'),
    ('URACIL', 'chemo'),
    ('VALRUBICIN', 'chemo'),
    ('VINBLASTINE', 'chemo'),
    ('VINCRISTINE', 'chemo'),
    ('VINDESINE', 'chemo'),
    ('VINFLUNINE', 'chemo'),
    ('VINORELBINE', 'chemo'),
    ('ABARELIX', 'endo'),
    ('ABIRATERONE', 'endo'),
    ('AMINOGLUTETHIMIDE', 'endo'),
    ('ANASTROZOLE', 'endo'),
    ('APALUTAMIDE', 'endo'),
    ('BICALUTAMIDE', 'endo'),
    ('BUSERELIN', 'endo'),
    ('CYPROTERONE', 'endo'),
    ('DAROLUTAMIDE', 'endo'),
    ('DEGARELIX', 'endo'),
    ('ENZALUTAMIDE', 'endo'),
    ('ESTRAMUSTINE', 'endo'),
    ('EXEMESTANE', 'endo'),
    ('FLUTAMIDE', 'endo'),
    ('FULVESTRANT', 'endo'),
    ('GOSERELIN', 'endo'),
    ('HISTRELIN', 'endo'),
    ('LETROZOLE', 'endo'),
    ('LEUPROLIDE', 'endo'),
    ('MITOTANE', 'endo'),
    ('NILUTAMIDE', 'endo'),
    ('RELUGOLIX', 'endo'),
    ('TAMOXIFEN', 'endo'),
    ('TESTOLACTONE', 'endo'),
    ('TOREMIFENE', 'endo'),
    ('TRIPTORELIN', 'endo'),
    ('ABEMACICLIB', 'target'),
    ('ACALABRUTINIB', 'target'),
    ('ADAGRASIB', 'target'),
    ('AFATINIB', 'target'),
    ('AFLIBERCEPT', 'target'),
    ('ALECTINIB', 'target'),
    ('ALEMTUZUMAB', 'target'),
    ('ALPELISIB', 'target'),
    ('AMIVANTAMAB', 'target'),
    ('ARSENIC', 'target'),
    ('ASCIMINIB', 'target'),
    ('AVAPRITINIB', 'target'),
    ('AVUTOMETINIB', 'target'),
    ('AXITINIB', 'target'),
    ('BELANTAMAB', 'target'),
    ('BELINOSTAT', 'target'),
    ('BELZUTIFAN', 'target'),
    ('BEVACIZUMAB', 'target'),
    ('BEXAROTENE', 'target'),
    ('BINIMETINIB', 'target'),
    ('BLINATUMOMAB', 'target'),
    ('BORTEZOMIB', 'target'),
    ('BOSUTINIB', 'target'),
    ('BRENTUXIMAB', 'target'),
    ('BRIGATINIB', 'target'),
    ('CABOZANTINIB', 'target'),
    ('CAPIVASERTIB', 'target'),
    ('CAPMATINIB', 'target'),
    ('CARFILZOMIB', 'target'),
    ('CERITINIB', 'target'),
    ('CETUXIMAB', 'target'),
    ('COBIMETINIB', 'target'),
    ('COPANLISIB', 'target'),
    ('CRIZOTINIB', 'target'),
    ('DABRAFENIB', 'target'),
    ('DACOMITINIB', 'target'),
    ('DARATUMUMAB', 'target'),
    ('DASATINIB', 'target'),
    ('DEFACTINIB', 'target'),
    ('DEMCIZUMAB', 'target'),
    ('DOSTARLIMAB', 'target'),
    ('DATOPOTAMAB', 'target'),
    ('DINUTUXIMAB', 'target'),
    ('DUVELISIB', 'target'),
    ('EFLORNITHINE', 'target'),
    ('ELACESTRANT', 'target'),
    ('ELOTUZUMAB', 'target'),
    ('ELRANATAMAB', 'target'),
    ('ENASIDENIB', 'target'),
    ('ENCORAFENIB', 'target'),
    ('ENFORTUMAB', 'target'),
    ('ENSARTINIB', 'target'),
    ('ENTRECTINIB', 'target'),
    ('EPCORITAMAB', 'target'),
    ('ERDAFITINIB', 'target'),
    ('ERLOTINIB', 'target'),
    ('EVEROLIMUS', 'target'),
    ('FEDRATINIB', 'target'),
    ('FRUQUINTINIB', 'target'),
    ('FUTIBATINIB', 'target'),
    ('GEFITINIB', 'target'),
    ('GEMTUZUMAB', 'target'),
    ('GILTERITINIB', 'target'),
    ('GLASDEGIB', 'target'),
    ('IBRUTINIB', 'target'),
    ('IBRITUMOMAB', 'target'),
    ('IDELALISIB', 'target'),
    ('IMATINIB', 'target'),
    ('IMETELSTAT', 'target'),
    ('INAVOLISIB', 'target'),
    ('INFIGRATINIB', 'target'),
    ('INOTUZUMAB', 'target'),
    ('ISATUXIMAB', 'target'),
    ('IVOSIDENIB', 'target'),
    ('IXAZOMIB', 'target'),
    ('LAPATINIB', 'target'),
    ('LAROTRECTINIB', 'target'),
    ('LENALIDOMIDE', 'target'),
    ('LENVATINIB', 'target'),
    ('LONCASTUXIMAB', 'target'),
    ('LORLATINIB', 'target'),
    ('MARGETUXIMAB', 'target'),
    ('MIDOSTAURIN', 'target'),
    ('MIRDAMETINIB', 'target'),
    ('MIRVETUXIMAB', 'target'),
    ('MOBOCERTINIB', 'target'),
    ('MOGAMULIZUMAB', 'target'),
    ('MOMELOTINIB', 'target'),
    ('MOSUNETUZUMAB', 'target'),
    ('MOXETUMOMAB', 'target'),
    ('NAXITAMAB', 'target'),
    ('NECITUMUMAB', 'target'),
    ('NERATINIB', 'target'),
    ('NILOTINIB', 'target'),
    ('NIRAPARIB', 'target'),
    ('NIROGACESTAT', 'target'),
    ('OBINUTUZUMAB', 'target'),
    ('OFATUMUMAB', 'target'),
    ('OLAPARIB', 'target'),
    ('OLARATUMAB', 'target'),
    ('OLUTASIDENIB', 'target'),
    ('OSIMERTINIB', 'target'),
    ('PACRITINIB', 'target'),
    ('PALBOCICLIB', 'target'),
    ('PAMREVLUMAB', 'target'),
    ('PANITUMUMAB', 'target'),
    ('PANOBINOSTAT', 'target'),
    ('PAZOPANIB', 'target'),
    ('PEMIGATINIB', 'target'),
    ('PERTUZUMAB', 'target'),
    ('PEXIDARTINIB', 'target'),
    ('PIMITESPIB', 'target'),
    ('PIRTOBRUTINIB', 'target'),
    ('PLITIDEPSIN', 'target'),
    ('POLATUZUMAB', 'target'),
    ('POMALIDOMIDE', 'target'),
    ('PONATINIB', 'target'),
    ('PRALSETINIB', 'target'),
    ('QUIZARTINIB', 'target'),
    ('RAMUCIRUMAB', 'target'),
    ('REGORAFENIB', 'target'),
    ('REVUMENIB', 'target'),
    ('RIBOCICLIB', 'target'),
    ('RIPRETINIB', 'target'),
    ('RITUXIMAB', 'target'),
    ('ROMIDEPSIN', 'target'),
    ('RUCAPARIB', 'target'),
    ('RUXOLITINIB', 'target'),
    ('SACITUZUMAB', 'target'),
    ('SELINEXOR', 'target'),
    ('SELPERCATINIB', 'target'),
    ('SELUMETINIB', 'target'),
    ('SILTUXIMAB', 'target'),
    ('SONIDEGIB', 'target'),
    ('SORAFENIB', 'target'),
    ('SOTORASIB', 'target'),
    ('SUNITINIB', 'target'),
    ('TAFASITAMAB', 'target'),
    ('TAGRAXOFUSP', 'target'),
    ('TALAZOPARIB', 'target'),
    ('TALQUETAMAB', 'target'),
    ('TAZEMETOSTAT', 'target'),
    ('TEBENTAFUSP', 'target'),
    ('TECLISTAMAB', 'target'),
    ('TELISOTUZUMAB', 'target'),
    ('TELOTRISTAT', 'target'),
    ('TEMSIROLIMUS', 'target'),
    ('TEPOTINIB', 'target'),
    ('THALIDOMIDE', 'target'),
    ('TISOTUMAB', 'target'),
    ('TIVOZANIB', 'target'),
    ('TOSITUMOMAB', 'target'),
    ('TOVORAFENIB', 'target'),
    ('TRAMETINIB', 'target'),
    ('TRASTUZUMAB', 'target'),
    ('TREMELIMUMAB', 'target'),
    ('TRETINOIN', 'target'),
    ('TUCATINIB', 'target'),
    ('UMBRALISIB', 'target'),
    ('UPIFITAMAB', 'target'),
    ('VANDETANIB', 'target'),
    ('VELIPARIB', 'target'),
    ('VEMURAFENIB', 'target'),
    ('VENETOCLAX', 'target'),
    ('VIMSELTINIB', 'target'),
    ('VISMODEGIB', 'target'),
    ('VORINOSTAT', 'target'),
    ('ZANUBRUTINIB', 'target'),
    ('GLOFITAMAB', 'target'),
    ('LAZERTINIB', 'target'),
    ('REPOTRECTINIB', 'target'),
    ('TARLATAMAB', 'target'),
    ('VORASIDENIB', 'target'),
    ('ZANIDATAMAB', 'target'),
    ('ZENOCUTUZUMAB', 'target'),
    ('ZOLBETUXIMAB', 'target'),
    ('ATEZOLIZUMAB', 'immune-ici'),
    ('AVELUMAB', 'immune-ici'),
    ('CEMIPLIMAB', 'immune-ici'),
    ('COSIBELIMAB', 'immune-ici'),
    ('DURVALUMAB', 'immune-ici'),
    ('IPILIMUMAB', 'immune-ici'),
    ('NIVOLUMAB', 'immune-ici'),
    ('PEMBROLIZUMAB', 'immune-ici'),
    ('PENPULIMAB', 'immune-ici'),
    ('RETIFANLIMAB', 'immune-ici'),
    ('TISLELIZUMAB', 'immune-ici'),
    ('TORIPALIMAB', 'immune-ici'),
    ('AFAMITRESGENE', 'immune-cart'),
    ('AXICABTAGENE', 'immune-cart'),
    ('BREXUCABTAGENE', 'immune-cart'),
    ('CILTACABTAGENE', 'immune-cart'),
    ('IDECABTAGENE', 'immune-cart'),
    ('LISOCABTAGENE', 'immune-cart'),
    ('NADOFARAGENE', 'immune-cart'),
    ('OBECABTAGENE', 'immune-cart'),
    ('TISAGENLECLEUCEL', 'immune-cart'),
    ('ALDESLEUKIN', 'immune-other'),
    ('DENILEUKIN', 'immune-other'),
    ('INTERFERON', 'immune-other'),
    ('LEVAMISOLE', 'immune-other'),
    ('PEGINTERFERON', 'immune-other'),
    ('ROPEGINTERFERON', 'immune-other'),
    ('SIPULEUCEL', 'immune-other'),
    ('TALIMOGENE', 'immune-other'),
    ('LIFILEUCEL', 'immune-other')
;


-- =====================================================
-- TEMP TABLE: diagnosis classification
-- =====================================================
DROP TABLE IF EXISTS #tmp_classified_diagnosis;
WITH CTE_ICD10 AS (
    SELECT
        "DiagnosisKey",
        "Value"
    FROM "DiagnosisTerminologyDim"
    WHERE "Type" = 'ICD-10-CM'
        AND (
            -- CancerType filters
            (
                (
                    "Value" LIKE 'C__.%'
                    OR "Value" IN ('C01', 'C07', 'C12', 'C19', 'C20', 'C23', 'C33', 'C37', 'C52', 'C55', 'C58', 'C61', 'C73', 'D45')
                    OR "Value" LIKE 'D45.%' -- add PV
                    OR "Value" LIKE 'D46.%' -- add MDS
                    OR "Value" LIKE 'D47.0%' -- add SM
                    OR "Value" LIKE 'D47.1%' -- add PMF
                    OR "Value" LIKE 'D47.3%' -- add ET
                    OR "Value" LIKE 'D47.4%' -- add PMF
                )
                AND "Value" NOT LIKE 'C44.%' -- remove skin cancer
                AND "Value" NOT LIKE 'C4A.%' -- remove skin cancer (Merkel)
            )
            -- VTEType filters
            OR "Value" IN (
                'I26.02','I26.09','I26.92','I26.93','I26.94','I26.99',  -- Acute PE

                'I80.10','I80.11','I80.12','I80.13','I80.201','I80.202','I80.203','I80.209','I80.211','I80.212','I80.213','I80.219','I80.221',
                'I80.222','I80.223','I80.229','I80.231','I80.232','I80.233','I80.239','I80.241','I80.242','I80.243','I80.249','I80.251','I80.252',
                'I80.253','I80.259','I80.291','I80.292','I80.293','I80.299','I82.220','I82.401','I82.402','I82.403','I82.409','I82.411','I82.412',
                'I82.413','I82.419','I82.421','I82.422','I82.423','I82.429','I82.431','I82.432','I82.433','I82.439','I82.441','I82.442','I82.443',
                'I82.449','I82.451','I82.452','I82.453','I82.459','I82.461','I82.462','I82.463','I82.469','I82.491','I82.492','I82.493','I82.499',
                'I82.4Y1','I82.4Y2','I82.4Y3','I82.4Y9','I82.4Z1','I82.4Z2','I82.4Z3','I82.4Z9',  -- Acute LE-DVT

                'I82.210','I82.290','I82.621','I82.622','I82.623','I82.629','I82.A11','I82.A12','I82.A13','I82.A19','I82.B11','I82.B12','I82.B13',
                'I82.B19','I82.C11','I82.C12','I82.C13','I82.C19','I82.601','I82.602','I82.603','I82.609',  -- Acute UE-DVT

                'I27.82',  -- Chronic PE

                'I82.211','I82.221','I82.291','I82.501','I82.502','I82.503','I82.509','I82.511','I82.512','I82.513','I82.519','I82.521',
                'I82.522','I82.523','I82.529','I82.531','I82.532','I82.533','I82.539','I82.541','I82.542','I82.543','I82.549','I82.551','I82.552',
                'I82.553','I82.559','I82.561','I82.562','I82.563','I82.569','I82.591','I82.592','I82.593','I82.599','I82.5Y1','I82.5Y2','I82.5Y3',
                'I82.5Y9','I82.5Z1','I82.5Z2','I82.5Z3','I82.5Z9','I82.701','I82.702','I82.703','I82.709','I82.721','I82.722','I82.723','I82.729',
                'I82.891','I82.91','I82.A21','I82.A22','I82.A23','I82.A29','I82.B21','I82.B22','I82.B23','I82.B29','I82.C21','I82.C22','I82.C23',
                'I82.C29',  -- Chronic DVT

                'Z86.711','Z86.718'  -- Historic VTE
            )
            -- isMetastatic filters
            OR ("Value" LIKE 'C78.%' OR "Value" LIKE 'C79.%' OR "Value" LIKE 'C80.%' OR "Value" LIKE 'C7B.%')
            -- isParalysis filters
            OR (
                "Value" IN ('G04.1', 'G11.4', 'G80.1', 'G80.2')
                OR "Value" LIKE 'G81%' OR "Value" LIKE 'G82%' OR "Value" LIKE 'G83.0%' OR "Value" LIKE 'G83.1%'
                OR "Value" LIKE 'G83.2%' OR "Value" LIKE 'G83.3%' OR "Value" LIKE 'G83.4%' OR "Value" LIKE 'G83.9%'
            )
        )
),
CTE_ICDMapping AS (
    SELECT
        "DiagnosisKey",
        "Value",
        CASE
            WHEN 
                "Value" LIKE 'C0_.%' OR "Value" IN ('C01', 'C07', 'C12', 'C33') OR "Value" LIKE 'C10.%' OR "Value" LIKE 'C11.%' OR "Value" LIKE 'C12.%'
                OR "Value" LIKE 'C13.%' OR "Value" LIKE 'C14.%' OR "Value" LIKE 'C30.%' OR "Value" LIKE 'C31.%' 
                OR "Value" LIKE 'C32.%' OR "Value" LIKE 'C33.%' THEN 'head and neck'
            WHEN "Value" LIKE 'C15.%' THEN 'gi_esophageal'
            WHEN "Value" LIKE 'C16.%' THEN 'gi_gastric'
            WHEN "Value" LIKE 'C17.%' THEN 'gi_intestinal'
            WHEN "Value" LIKE 'C18.%' OR "Value" IN ('C19', 'C20') OR "Value" LIKE 'C19.%' OR "Value" LIKE 'C20.%' THEN 'gi_colorectal'
            WHEN "Value" LIKE 'C21.%' THEN 'gi_anal'
            WHEN "Value" LIKE 'C22.%' AND "Value" <> 'C22.1' THEN 'gi_liver'
            WHEN "Value" LIKE 'C23.%' OR "Value" IN ('C23') OR "Value" LIKE 'C24.%' OR "Value" = 'C22.1' THEN 'gi_cholangio and gallbladder'
            WHEN "Value" LIKE 'C25.%' THEN 'gi_pancreas'
            WHEN "Value" LIKE 'C34.%' THEN 'lung'
            WHEN "Value" LIKE 'C37.%' OR "Value" IN ('C37') OR "Value" LIKE 'C38.%' OR "Value" LIKE 'C45.%' THEN 'thoracic_other'
            WHEN "Value" LIKE 'C40.%' OR "Value" LIKE 'C41.%' OR ("Value" LIKE 'C49.%' AND "Value" NOT LIKE 'C49.A%') 
                THEN 'sarcoma_soft tissue'
            WHEN "Value"  LIKE 'C48.%' THEN 'peritoneal/retroperitoneal'
            WHEN "Value" LIKE 'C49.A%' THEN 'sarcoma_gist'
            WHEN "Value" LIKE 'C46.%' THEN 'sarcoma_kaposi'
            WHEN "Value" LIKE 'C43.%' THEN 'melanoma'
            WHEN "Value" LIKE 'C50.%' THEN 'breast'
            WHEN "Value" LIKE 'C51.%' THEN 'gyn_vulvar'
            WHEN "Value" LIKE 'C52.%' OR "Value" IN ('C52') THEN 'gyn_vaginal'
            WHEN "Value" LIKE 'C53.%' THEN 'gyn_cervical'
            WHEN "Value" LIKE 'C54.%' OR "Value" LIKE 'C55.%' OR "Value" IN ('C55') THEN 'gyn_uterine'
            WHEN "Value" LIKE 'C56.%' OR "Value" LIKE 'C57.0%'  THEN 'gyn_ovarian'
            WHEN "Value" LIKE 'C60.%' THEN 'gu_penile'
            WHEN "Value" LIKE 'C61.%' OR "Value" IN ('C61') THEN 'prostate'
            WHEN "Value" LIKE 'C62.%' THEN 'gu_testicular'
            WHEN "Value" LIKE 'C64.%' THEN 'gu_kidney'
            WHEN "Value" LIKE 'C65.%' OR "Value" LIKE 'C66.%' THEN 'gu_urothelial'
            WHEN "Value" LIKE 'C67.%' THEN 'gu_bladder'
            WHEN "Value" LIKE 'C69.%' THEN 'eye and orbit'
            WHEN "Value" LIKE 'C70.%' OR "Value" LIKE 'C71.%' THEN 'cns'
            WHEN "Value" LIKE 'C47.%' OR "Value" LIKE 'C72.%' THEN 'nervous system'
            WHEN "Value" LIKE 'C73.%' OR "Value" IN ('C73') THEN 'thyroid'
            WHEN "Value" LIKE 'C74.%' OR "Value" LIKE 'C75.%' THEN 'endocrine'
            WHEN "Value" LIKE 'C7A.%' THEN 'net_malignant/carcinoid'
--            WHEN "Value" LIKE 'C77.%' OR "Value" LIKE 'C78.%' OR "Value" LIKE 'C79.%' OR "Value" LIKE 'C80.%'
--                OR ("Value" LIKE 'C7B.%' AND "Value" <> 'C7B.1') THEN 'secondary/metastatic'
            WHEN "Value" LIKE 'C81.%' THEN 'lymphoma_hodgkin'
            WHEN "Value" LIKE 'C82.%' AND "Value" NOT LIKE 'C82.6%' THEN 'lymphoma_follicular'
            WHEN "Value" LIKE 'C83.0%' OR "Value" LIKE 'C91.1%' THEN 'lymphoma_cll/sll'
            WHEN "Value" LIKE 'C83.1%' THEN 'lymphoma_mantle'
            WHEN "Value" LIKE 'C83.2%' OR "Value" LIKE 'C83.3%' OR "Value" LIKE 'C83.4%' OR "Value" LIKE 'C83.6%' 
                OR "Value" LIKE 'C83.8%' OR "Value" LIKE 'C85.2%' OR "Value" LIKE 'C85.8%' THEN 'lymphoma_dlbcl'
            WHEN "Value" LIKE 'C83.5%' THEN 'lymphoma_lymphoblastic'
            WHEN "Value" LIKE 'C83.7%' OR "Value" LIKE 'C91.A%' THEN 'lymphoma_burkitt'
            WHEN ("Value" LIKE 'C84.%' OR "Value" LIKE 'C86.%' OR "Value" LIKE 'C91.5%' OR "Value" LIKE 'C91.6%')
                AND ("Value" NOT LIKE 'C84.0%' AND "Value" NOT LIKE 'C84.1%' AND "Value" NOT LIKE 'C84.A%' 
                AND "Value" NOT LIKE 'C86.3%' AND "Value" NOT LIKE 'C86.6%') THEN 'lymphoma_systemic t and nk'
            WHEN "Value" LIKE 'C84.0%' OR "Value" LIKE 'C84.1%' OR "Value" LIKE 'C84.A%' OR "Value" LIKE 'C86.3%' 
                OR "Value" LIKE 'C86.6%' THEN 'lymphoma_cutaneous t cell'
            WHEN "Value" LIKE 'C88.%' OR "Value" LIKE 'C91.2%' OR "Value" LIKE 'C91.3%' OR "Value" LIKE 'C91.4%'
                THEN 'lymphoma_other'
            WHEN "Value" LIKE 'C90.%' THEN 'myeloma'
            WHEN "Value" LIKE 'C91.0%' THEN 'leukemia_all'
            WHEN "Value" LIKE 'C92.0%' OR "Value" LIKE 'C92.3%' OR "Value" LIKE 'C92.4%' OR "Value" LIKE 'C92.5%' 
                OR "Value" LIKE 'C92.6%' OR "Value" LIKE 'C92.A%' OR "Value" LIKE 'C93.0%' OR "Value" LIKE 'C94.0%' 
                OR "Value" LIKE 'C94.2%' OR "Value" LIKE 'C94.3%' OR "Value" LIKE 'C94.4%' OR "Value" LIKE 'C95.0%'
                THEN 'leukemia_aml'
            WHEN "Value" LIKE 'C92.1%' THEN 'mpn_cml'
            WHEN "Value" LIKE 'C92.2%' OR "Value" LIKE 'C93.1%' OR "Value" LIKE 'C93.2%' OR "Value" LIKE 'C93.3%' 
                THEN 'mpn_cmml'
            WHEN "Value" LIKE 'C96.2%' OR "Value" LIKE 'D47.0%' THEN 'mpn_mast'
            WHEN "Value" LIKE 'D45.%' OR "Value" = 'D45' THEN 'mpn_pv'
            WHEN "Value" LIKE 'D47.3%' THEN 'mpn_et'
            WHEN "Value" LIKE 'D47.1%' OR "Value" LIKE 'D47.4%' THEN 'mpn_pmf'
            WHEN "Value" LIKE 'D46.%' OR "Value" LIKE 'C94.6%' THEN 'mds'
--            WHEN "Value" LIKE 'C26.%' -- unspecified GI cancer
--                OR "Value" LIKE 'C39.%' -- unspecified thoracic cancer
--                OR ("Value" LIKE 'C57.%' AND "Value" NOT LIKE 'C57.0%') -- unspecified GYN cancer (genital)
--                OR "Value" LIKE 'C58.%' OR "Value" = 'C58' -- unspecified GYN cancer (placenta)
--                OR "Value" LIKE 'C63.%' -- unspecified GU cancer (genital)
--                OR "Value" LIKE 'C68.%' -- unspecified GU cancer (urethra)
--                OR "Value" LIKE 'C76.%' -- ill-defined site
--                OR "Value" LIKE 'C82.6%' OR "Value" LIKE 'C83.9%' -- unspecified non-follicular lymphoma
--                OR "Value" LIKE 'C85.1%' OR "Value" LIKE 'C85.9%' -- unspecified non-Hodgkin lymphoma
--                OR "Value" LIKE 'C91.9%' OR "Value" LIKE 'C91.Z%' -- unspecified lymphoid leukemia
--                OR "Value" LIKE 'C92.9%' OR "Value" LIKE 'C92.Z%' -- unspecified myeloid leukemia
--                OR "Value" LIKE 'C93.9%' OR "Value" LIKE 'C93.Z%' -- unspecified monocytic leukemia
--                OR "Value" LIKE 'C94.8%' -- unspecified leukemia
--                OR "Value" LIKE 'C95.1%' OR "Value" LIKE 'C95.9%' -- unspecified leukemia
--                OR ("Value" LIKE 'C96.%' AND "Value" NOT LIKE 'C96.2%') -- unspecified heme except systemic mastocytosis
--            THEN 'unspecified'
            ELSE NULL
        END AS "CancerType",
        CASE
            WHEN 
                "Value" IN ('I26.02','I26.09','I26.92','I26.93','I26.94','I26.99') THEN 'Acute PE'
            WHEN
                "Value" IN ('I80.10','I80.11','I80.12','I80.13','I80.201','I80.202','I80.203','I80.209','I80.211','I80.212','I80.213','I80.219','I80.221',
                    'I80.222','I80.223','I80.229','I80.231','I80.232','I80.233','I80.239','I80.241','I80.242','I80.243','I80.249','I80.251','I80.252',
                    'I80.253','I80.259','I80.291','I80.292','I80.293','I80.299','I82.220','I82.401','I82.402','I82.403','I82.409','I82.411','I82.412',
                    'I82.413','I82.419','I82.421','I82.422','I82.423','I82.429','I82.431','I82.432','I82.433','I82.439','I82.441','I82.442','I82.443',
                    'I82.449','I82.451','I82.452','I82.453','I82.459','I82.461','I82.462','I82.463','I82.469','I82.491','I82.492','I82.493','I82.499',
                    'I82.4Y1','I82.4Y2','I82.4Y3','I82.4Y9','I82.4Z1','I82.4Z2','I82.4Z3','I82.4Z9') THEN 'Acute LE-DVT'
            WHEN
                "Value" IN ('I82.210','I82.290','I82.621','I82.622','I82.623','I82.629','I82.A11','I82.A12','I82.A13','I82.A19','I82.B11','I82.B12','I82.B13',
                    'I82.B19','I82.C11','I82.C12','I82.C13','I82.C19','I82.601','I82.602','I82.603','I82.609') THEN 'Acute UE-DVT'
            WHEN 
                "Value" IN ('I27.82') THEN 'Chronic PE'
            WHEN 
                "Value" IN ('I82.211','I82.221','I82.291','I82.501','I82.502','I82.503','I82.509','I82.511','I82.512','I82.513','I82.519','I82.521',
                    'I82.522','I82.523','I82.529','I82.531','I82.532','I82.533','I82.539','I82.541','I82.542','I82.543','I82.549','I82.551','I82.552',
                    'I82.553','I82.559','I82.561','I82.562','I82.563','I82.569','I82.591','I82.592','I82.593','I82.599','I82.5Y1','I82.5Y2','I82.5Y3',
                    'I82.5Y9','I82.5Z1','I82.5Z2','I82.5Z3','I82.5Z9','I82.701','I82.702','I82.703','I82.709','I82.721','I82.722','I82.723','I82.729',
                    'I82.891','I82.91','I82.A21','I82.A22','I82.A23','I82.A29','I82.B21','I82.B22','I82.B23','I82.B29','I82.C21','I82.C22','I82.C23',
                    'I82.C29') THEN 'Chronic DVT'
            WHEN 
                "Value" IN ('Z86.711','Z86.718') THEN 'Historic VTE'
            ELSE NULL
        END AS "VTEType",
        CASE
            WHEN "Value" LIKE 'C78.%' OR "Value" LIKE 'C79.%' OR "Value" LIKE 'C80.%' OR "Value" LIKE 'C7B.%'
            THEN 1 ELSE 0
        END AS "IsMetastatic",
        CASE
            WHEN "Value" IN ('G04.1', 'G11.4', 'G80.1', 'G80.2') OR "Value" LIKE 'G81%' OR "Value" LIKE 'G82%' OR "Value" LIKE 'G83.0%' OR "Value" LIKE 'G83.1%' OR "Value" LIKE 'G83.2%' OR "Value" LIKE 'G83.3%' OR "Value" LIKE 'G83.4%' OR "Value" LIKE 'G83.9%'
            THEN 1 ELSE 0
        END AS "IsParalysis"
    FROM CTE_ICD10
)
SELECT *
INTO #tmp_classified_diagnosis
FROM CTE_ICDMapping
;

CREATE NONCLUSTERED INDEX IX_tmp_classified_diagnosis_DxKey ON #tmp_classified_diagnosis ("DiagnosisKey");


-- =====================================================
-- TEMP TABLE: mappings used to clean race/ethnicity
-- =====================================================
DROP TABLE IF EXISTS #tmp_country_2_race;
DROP TABLE IF EXISTS #tmp_lang_2_race;

CREATE TABLE #tmp_country_2_race (
    country  VARCHAR(300) NOT NULL PRIMARY KEY,
    race     VARCHAR(300) NOT NULL
);

CREATE TABLE #tmp_lang_2_race (
    language    VARCHAR(300)  NOT NULL PRIMARY KEY,
    race        VARCHAR(300)  NOT NULL
);

INSERT INTO #tmp_country_2_race (country, race) VALUES
    -- Europe and Middle East
    ('AUSTRIA', 'White'),
    ('BELGIUM', 'White'),
    ('BOSNIA AND HERZEGOVINA', 'White'),
    ('BULGARIA', 'White'),
    ('CROATIA', 'White'),
    ('CZECH REPUBLIC', 'White'),
    ('DENMARK', 'White'),
    ('ESTONIA', 'White'),
    ('FINLAND', 'White'),
    ('FRANCE', 'White'),
    ('GERMANY', 'White'),
    ('GREECE', 'White'),
    ('HUNGARY', 'White'),
    ('ICELAND', 'White'),
    ('IRELAND', 'White'),
    ('ITALY', 'White'),
    ('LATVIA', 'White'),
    ('LITHUANIA', 'White'),
    ('LUXEMBOURG', 'White'),
    ('MALTA', 'White'),
    ('NETHERLANDS', 'White'),
    ('NORWAY', 'White'),
    ('POLAND', 'White'),
    ('PORTUGAL', 'White'),
    ('ROMANIA', 'White'),
    ('SERBIA', 'White'),
    ('SLOVAKIA', 'White'),
    ('SLOVENIA', 'White'),
    ('SPAIN', 'White'),
    ('SWEDEN', 'White'),
    ('SWITZERLAND', 'White'),
    ('UNITED KINGDOM', 'White'),
    ('YUGOSLAVIA', 'White'),
    ('BAHRAIN', 'White'),
    ('CYPRUS', 'White'),
    ('EGYPT', 'White'),
    ('IRAN', 'White'),
    ('IRAQ', 'White'),
    ('ISRAEL', 'White'),
    ('JORDAN', 'White'),
    ('KUWAIT', 'White'),
    ('LEBANON', 'White'),
    ('QATAR', 'White'),
    ('SAUDI ARABIA', 'White'),
    ('SYRIA', 'White'),
    ('TURKEY', 'White'),
    ('UNITED ARAB EMIRATES', 'White'),
    ('YEMEN', 'White'),
    -- Africa
    ('ALGERIA', 'Black or African American'),
    ('ANGOLA', 'Black or African American'),
    ('BENIN', 'Black or African American'),
    ('BOTSWANA', 'Black or African American'),
    ('BURKINA FASO', 'Black or African American'),
    ('BURUNDI', 'Black or African American'),
    ('CAMEROON', 'Black or African American'),
    ('CAPE VERDE', 'Black or African American'),
    ('CENTRAL AFRICAN REPUBLIC', 'Black or African American'),
    ('CHAD', 'Black or African American'),
    ('COMOROS', 'Black or African American'),
    ('CONGO', 'Black or African American'),
    ('DJIBOUTI', 'Black or African American'),
    ('EQUATORIAL GUINEA', 'Black or African American'),
    ('ERITREA', 'Black or African American'),
    ('ESWATINI', 'Black or African American'),
    ('ETHIOPIA', 'Black or African American'),
    ('GABON', 'Black or African American'),
    ('GAMBIA', 'Black or African American'),
    ('GHANA', 'Black or African American'),
    ('GUINEA', 'Black or African American'),
    ('GUINEA-BISSAU', 'Black or African American'),
    ('KENYA', 'Black or African American'),
    ('LESOTHO', 'Black or African American'),
    ('LIBERIA', 'Black or African American'),
    ('LIBYA', 'Black or African American'),
    ('MADAGASCAR', 'Black or African American'),
    ('MALAWI', 'Black or African American'),
    ('MALI', 'Black or African American'),
    ('MAURITANIA', 'Black or African American'),
    ('MAURITIUS', 'Black or African American'),
    ('MOROCCO', 'Black or African American'),
    ('MOZAMBIQUE', 'Black or African American'),
    ('NAMIBIA', 'Black or African American'),
    ('NIGER', 'Black or African American'),
    ('NIGERIA', 'Black or African American'),
    ('RWANDA', 'Black or African American'),
    ('SENEGAL', 'Black or African American'),
    ('SEYCHELLES', 'Black or African American'),
    ('SIERRA LEONE', 'Black or African American'),
    ('SOMALIA', 'Black or African American'),
    ('SOUTH AFRICA', 'Black or African American'),
    ('SOUTH SUDAN', 'Black or African American'),
    ('SUDAN', 'Black or African American'),
    ('TANZANIA', 'Black or African American'),
    ('TOGO', 'Black or African American'),
    ('TUNISIA', 'Black or African American'),
    ('UGANDA', 'Black or African American'),
    ('ZAMBIA', 'Black or African American'),
    ('ZIMBABWE', 'Black or African American'),
    -- Asia
    ('AFGHANISTAN', 'Asian'),
    ('ARMENIA', 'Asian'),
    ('AZERBAIJAN', 'Asian'),
    ('BANGLADESH', 'Asian'),
    ('BHUTAN', 'Asian'),
    ('BRUNEI', 'Asian'),
    ('CAMBODIA', 'Asian'),
    ('CHINA', 'Asian'),
    ('GEORGIA', 'Asian'),
    ('INDIA', 'Asian'),
    ('INDONESIA', 'Asian'),
    ('JAPAN', 'Asian'),
    ('KAZAKHSTAN', 'Asian'),
    ('NORTH KOREA', 'Asian'),
    ('SOUTH KOREA', 'Asian'),
    ('KYRGYZSTAN', 'Asian'),
    ('LAOS', 'Asian'),
    ('MALAYSIA', 'Asian'),
    ('MALDIVES', 'Asian'),
    ('MONGOLIA', 'Asian'),
    ('MYANMAR', 'Asian'),
    ('NEPAL', 'Asian'),
    ('PAKISTAN', 'Asian'),
    ('PHILIPPINES', 'Asian'),
    ('SINGAPORE', 'Asian'),
    ('SRI LANKA', 'Asian'),
    ('TAIWAN', 'Asian'),
    ('TAJIKISTAN', 'Asian'),
    ('THAILAND', 'Asian'),
    ('TURKMENISTAN', 'Asian'),
    ('UZBEKISTAN', 'Asian'),
    ('VIETNAM', 'Asian'),
    -- Latin America
    ('ARGENTINA', 'Other'),
    ('BAHAMAS', 'Other'),
    ('BARBADOS', 'Other'),
    ('BELIZE', 'Other'),
    ('BOLIVIA', 'Other'),
    ('BRAZIL', 'Other'),
    ('CHILE', 'Other'),
    ('COLOMBIA', 'Other'),
    ('COSTA RICA', 'Other'),
    ('CUBA', 'Other'),
    ('DOMINICA', 'Other'),
    ('DOMINICAN REPUBLIC', 'Other'),
    ('ECUADOR', 'Other'),
    ('EL SALVADOR', 'Other'),
    ('GRENADA', 'Other'),
    ('GUATEMALA', 'Other'),
    ('GUYANA', 'Other'),
    ('HAITI', 'Other'),
    ('HONDURAS', 'Other'),
    ('JAMAICA', 'Other'),
    ('MEXICO', 'Other'),
    ('NICARAGUA', 'Other'),
    ('PANAMA', 'Other'),
    ('PARAGUAY', 'Other'),
    ('PERU', 'Other'),
    ('SAINT KITTS AND NEVIS', 'Other'),
    ('SAINT LUCIA', 'Other'),
    ('SAINT VINCENT AND THE GRENADINES', 'Other'),
    ('SURINAME', 'Other'),
    ('TRINIDAD AND TOBAGO', 'Other'),
    ('URUGUAY', 'Other'),
    ('VENEZUELA', 'Other')
;


INSERT INTO #tmp_lang_2_race (language, race) VALUES
    ('BENGALI', 'Asian'),
    ('BURMESE', 'Asian'),
    ('CAMBODIAN', 'Asian'),
    ('CANTONESE', 'Asian'),
    ('CEBUANO', 'Asian'),
    ('CHINESE', 'Asian'),
    ('DARI', 'Asian'),
    ('FILIPINO', 'Asian'),
    ('GUJARATI', 'Asian'),
    ('HINDI', 'Asian'),
    ('INDONESIAN', 'Asian'),
    ('JAPANESE', 'Asian'),
    ('KAREN', 'Asian'),
    ('KHMER', 'Asian'),
    ('KOREAN', 'Asian'),
    ('LAO', 'Asian'),
    ('MALAY', 'Asian'),
    ('MALAYALAM', 'Asian'),
    ('MANDARIN', 'Asian'),
    ('MARATHI', 'Asian'),
    ('NEPALI', 'Asian'),
    ('PASHTO', 'Asian'),
    ('PERSIAN', 'Asian'),
    ('TAGALOG', 'Asian'),
    ('TAMIL', 'Asian'),
    ('TELUGU', 'Asian'),
    ('THAI', 'Asian'),
    ('TIGRINYA', 'Asian'),
    ('URDU', 'Asian'),
    ('VIETNAMESE', 'Asian'),
    ('ROHINGYA', 'Asian'),
    ('SPANISH', 'Other')
;


-- =====================================================
-- TEMP TABLE: mappings used for location name
-- =====================================================
DROP TABLE IF EXISTS #tmp_location_map;

CREATE TABLE #tmp_location_map (
    loc_name    VARCHAR(300) NOT NULL PRIMARY KEY,
    loc_cat     VARCHAR(50) NOT NULL
);

INSERT INTO #tmp_location_map (loc_name, loc_cat) VALUES
    -- BT/SC
    ('BEN TAUB GENERAL HOSPITAL', 'BT/SC'),
    ('SMITH CLINIC', 'BT/SC'),
    -- LBJ/OC
    ('LBJ GENERAL HOSPITAL', 'LBJ/OC'),
    ('OUTPATIENT CENTER', 'LBJ/OC'),
    -- BCM clinics
    ('CASA DE AMIGOS', 'BCM clinics'),
    ('CYPRESS HEALTH CENTER', 'BCM clinics'),
    ('GULFGATE', 'BCM clinics'),
    ('MLK', 'BCM clinics'),
    ('MONROE CLINIC', 'BCM clinics'),
    ('NORTHWEST', 'BCM clinics'),
    ('PASADENA PEDIATRIC AND ADOLESCENT HEALTH CENTER', 'BCM clinics'),
    ('QUENTIN MEASE HEALTH CENTER', 'BCM clinics'),
    ('QUENTIN MEASE HOSPITAL', 'BCM clinics'),
    ('SAREEN CLINIC', 'BCM clinics'),
    ('STRAWBERRY', 'BCM clinics'),
    ('SUNSET HEIGHTS CLINIC', 'BCM clinics'),
    ('THOMAS STREET', 'BCM clinics'),
    ('VALLBONA', 'BCM clinics'),
    -- UT clinics
    ('ACRES', 'UT clinics'),
    ('ALDINE', 'UT clinics'),
    ('BAYLAND GERIATRIC HEALTH CENTER', 'UT clinics'),
    ('BAYTOWN', 'UT clinics'),
    ('CLEVELAND E ODOM PEDIATRIC & ADOLESCENT HEALTH CENTER', 'UT clinics'),
    ('DANNY JACKSON HEALTH CENTER', 'UT clinics'),
    ('EL FRANCO LEE HEALTH CENTER', 'UT clinics'),
    ('SETTEGAST', 'UT clinics'),
    ('SQUATTY-LYONS', 'UT clinics')
;


DECLARE @sec0_end datetime2(3) = SYSDATETIME();
DECLARE @sec0_elapsed int = DATEDIFF(SECOND, @sec0_start, @sec0_end);
RAISERROR('Section 0 elapsed seconds: %d', 0, 1, @sec0_elapsed) WITH NOWAIT;


/*********************************************************************
** 1. Cohort tables
*********************************************************************/
DECLARE @sec1_start datetime2(3) = SYSDATETIME();

-- =====================================================
-- TEMP TABLE: treatment plans
-- =====================================================
DROP TABLE IF EXISTS #tmp_plan_base;
WITH CTE_PlanFlags AS (
    SELECT
        tplan."TreatmentPlanKey",
        MAX(
            CASE
                WHEN UPPER(cycle."CycleStatus") IN ('STARTED','COMPLETED')
                    AND UPPER(cycle."DayStatus") IN ('STARTED', 'COMPLETED')
                THEN CAST(1 AS tinyint) ELSE CAST(0 AS tinyint)
            END
        ) AS IsPastPlan,
        MAX(
            CASE
                WHEN (
                    -- either cycle or day status is planned
                    UPPER(cycle."CycleStatus") = 'PLANNED'
                    OR UPPER(cycle."DayStatus") = 'PLANNED'
                ) AND (
                    -- either not discontinued or discontinued after today
                    tplan."DiscontinuedDate" IS NULL
                    OR tplan."DiscontinuedDate" > CAST(GETDATE() AS date)
                )
                THEN CAST(1 AS tinyint) ELSE CAST(0 AS tinyint)
            END
        ) AS IsFuturePlan
    FROM "TreatmentPlanFact" tplan
    INNER JOIN "TreatmentPlanCycleDayFact" cycle
        ON tplan."TreatmentPlanKey" = cycle."TreatmentPlanKey"
            AND cycle."Count" = 1
            AND tplan."StartCycleNumber" = cycle."CycleNumber"
            AND (
                (tplan."DayNumberingStartsAtZero" = 1 AND cycle."DayNumber" = 0)
                OR (tplan."DayNumberingStartsAtZero" = 0 AND cycle."DayNumber" = 1)
            )
    WHERE tplan."Count" = 1
    GROUP BY tplan."TreatmentPlanKey"
)
SELECT
    tplan."TreatmentPlanKey",
    tplan."PlanEpicId",
    tplan."PatientDurableKey",
    cohort."PatientEpicId",
    tplan."PlanStartDate" AS "ScheduledPlanDate",
    tplan."TreatmentStartDate" AS "ScheduledTreatmentDate",
    tplan."PlanProviderDurableKey",
    tplan."DisplayName",
    tplan."Status",
    tplan."CreatedOnDate",
    tplan."_CreationInstant",
    tplan."_LastUpdatedInstant",
    tplan."DiscontinueReason",
    cte.IsPastPlan,
    cte.IsFuturePlan
INTO #tmp_plan_base
FROM "TreatmentPlanFact" tplan
INNER JOIN "PatientDim" cohort
    ON tplan."PatientDurableKey" = cohort."DurableKey"
        AND cohort."IsCurrent" = 1
INNER JOIN CTE_PlanFlags cte
    ON tplan."TreatmentPlanKey" = cte."TreatmentPlanKey"
WHERE tplan."Count" = 1
    AND UPPER(tplan."EpisodeType") = 'ONCOLOGY TREATMENT'
    AND UPPER(tplan."DisplayName") NOT LIKE '%NON-MALIGNANT%'
    -- We need past plans here to calculate PlanNum later
    AND (cte.IsPastPlan = 1 OR cte.IsFuturePlan = 1)
;

CREATE NONCLUSTERED INDEX IX_tmp_plan_base_PDKey_TPKey ON #tmp_plan_base ("PatientDurableKey", "TreatmentPlanKey");
CREATE NONCLUSTERED INDEX IX_tmp_plan_base_ScheduledPlanDate ON #tmp_plan_base ("ScheduledPlanDate");


-- =====================================================
-- TEMP TABLE: define index date per plan
-- =====================================================
DROP TABLE IF EXISTS #tmp_plan_index;
WITH CTE_EligibleOrders AS (
    SELECT
        medorder."PatientDurableKey",
        medorder."TreatmentPlanKey",
        medorder."MedicationOrderKey",
        medorder."StartDateKey" AS order_date_key
    FROM "TreatmentPlanMedicationOrderFact" medorder
    INNER JOIN #tmp_plan_base base
        ON medorder."PatientDurableKey" = base."PatientDurableKey"
            AND medorder."TreatmentPlanKey" = base."TreatmentPlanKey"
            AND base."IsFuturePlan" = 1
    INNER JOIN "TreatmentPlanFact" tplan
        ON tplan."TreatmentPlanKey" = medorder."TreatmentPlanKey"
            AND tplan."Count" = 1
    INNER JOIN "TreatmentPlanCycleDayFact" cycle
        ON cycle."TreatmentPlanKey" = medorder."TreatmentPlanKey"
            AND cycle."Count" = 1
            AND cycle."TreatmentPlanCycleDayKey" = medorder."TreatmentPlanCycleDayKey"
            AND cycle."CycleNumber" = tplan."StartCycleNumber"
            AND cycle."DayNumber" = 1
    WHERE medorder."Count" = 1
        AND UPPER(medorder."Type") = 'MEDICATIONS' 
        AND UPPER(medorder."OrderCategory") LIKE '%CHEMO%'
        AND medorder."StartDateKey" > 19000101  -- To exclude -1, -2, -3 dates
),
CTE_RankedOrder AS (
    SELECT
        "PatientDurableKey",
        "TreatmentPlanKey",
        "MedicationOrderKey",
        order_date_key,
        ROW_NUMBER() OVER (
            PARTITION BY "PatientDurableKey", "TreatmentPlanKey"
            ORDER BY order_date_key, "MedicationOrderKey"
        ) AS row_num
    FROM CTE_EligibleOrders
),
CTE_FirstOrder AS (
    SELECT * FROM CTE_RankedOrder WHERE row_num = 1
)
SELECT
    base."PatientDurableKey",
    base."TreatmentPlanKey",
    fo."MedicationOrderKey",
    NULL AS "TreatmentAdminStartDate",
    CASE WHEN fo.order_date_key IS NOT NULL
        THEN TRY_CONVERT(date, TRY_CONVERT(char(8), fo.order_date_key), 112)
    END AS "TreatmentOrderStartDate",
    CAST(GETDATE() AS date) AS "DataPullDate",
    CASE
        WHEN COALESCE(
            -- order start date if exists
            CASE WHEN fo.order_date_key IS NOT NULL
                THEN TRY_CONVERT(date, TRY_CONVERT(char(8), fo.order_date_key), 112)
            END,
            -- else, use ScheduledTreatmentDate
            base."ScheduledTreatmentDate"
        ) > CAST(GETDATE() AS date)
        THEN CAST(GETDATE() AS date)
        ELSE NULL
    END AS "IndexDate"
INTO #tmp_plan_index
FROM #tmp_plan_base base
LEFT JOIN CTE_FirstOrder fo
    ON base."PatientDurableKey" = fo."PatientDurableKey"
        AND base."TreatmentPlanKey" = fo."TreatmentPlanKey"
WHERE base."IsFuturePlan" = 1
;

CREATE NONCLUSTERED INDEX IX_tmp_plan_index_PDKey_TPKey ON #tmp_plan_index ("PatientDurableKey", "TreatmentPlanKey");


-- =====================================================
-- TEMP TABLE: final cohort table
-- =====================================================
DROP TABLE IF EXISTS #tmp_plan_cohort;
WITH all_plans AS (
    SELECT
        base."PatientDurableKey",
        base."PatientEpicId",
        base."TreatmentPlanKey",
        base."PlanEpicId",
        base."ScheduledPlanDate",
        base."ScheduledTreatmentDate",
        base."PlanProviderDurableKey",
        base."DisplayName" AS "PlanDisplayName",
        base."Status" AS "PlanStatus",
        base."CreatedOnDate" AS "PlanCreatedOnDate",
        base."DiscontinueReason" AS "PlanDiscontinueReason",
        base."_CreationInstant" AS "Plan_CreationInstant",
        base."_LastUpdatedInstant" AS "Plan_LastUpdatedInstant",
        base."IsFuturePlan",
        idx."TreatmentAdminStartDate",
        idx."TreatmentOrderStartDate",
        idx."DataPullDate",
        idx."IndexDate",
        ROW_NUMBER() OVER (
            PARTITION BY base."PatientDurableKey"
            ORDER BY base."ScheduledPlanDate", base."TreatmentPlanKey"
        ) AS "PlanNum",
        LAG(base."ScheduledPlanDate") OVER (
            PARTITION BY base."PatientDurableKey"
            ORDER BY base."ScheduledPlanDate", base."TreatmentPlanKey"
        ) AS "PrevScheduledPlanDate"
    FROM #tmp_plan_base base
    LEFT JOIN #tmp_plan_index idx
        ON base."PatientDurableKey" = idx."PatientDurableKey"
            AND base."TreatmentPlanKey" = idx."TreatmentPlanKey"
)
SELECT *
INTO #tmp_plan_cohort
FROM all_plans
WHERE "IsFuturePlan" = 1
    AND "IndexDate" IS NOT NULL
;

CREATE NONCLUSTERED INDEX IX_tmp_plan_cohort_PDKey_TPKey ON #tmp_plan_cohort ("PatientDurableKey", "TreatmentPlanKey");
CREATE NONCLUSTERED INDEX IX_tmp_plan_cohort_IndexDate ON #tmp_plan_cohort ("IndexDate");


-- =====================================================
-- TEMP TABLE: define date ranges
-- =====================================================
DROP TABLE IF EXISTS #tmp_plan_window;
SELECT
    "PatientDurableKey",
    "TreatmentPlanKey",
    -- date
    "DataPullDate",
    "IndexDate",
    DATEADD(month, -12, "IndexDate") AS "12MonthBefore",
    DATEADD(month, -3, "IndexDate") AS "3MonthBefore",
    DATEADD(month, 3, "IndexDate") AS "3MonthAfter",
    DATEADD(month, -6, "IndexDate") AS "6MonthBefore",
    DATEADD(month, 6, "IndexDate") AS "6MonthAfter",
    DATEADD(day, 1, "IndexDate") AS "1DayAfter",
    -- integer
    CONVERT(int, CONVERT(char(8), "DataPullDate", 112)) AS "DataPullDateKey",
    CONVERT(int, CONVERT(char(8), "IndexDate", 112)) AS "IndexDateKey",
    CONVERT(int, CONVERT(char(8), DATEADD(month,-12, "IndexDate"), 112)) AS "12MonthBeforeKey",
    CONVERT(int, CONVERT(char(8), DATEADD(month, -3, "IndexDate"), 112)) AS "3MonthBeforeKey",
    CONVERT(int, CONVERT(char(8), DATEADD(month, 3, "IndexDate"), 112)) AS "3MonthAfterKey",
    CONVERT(int, CONVERT(char(8), DATEADD(month, -6, "IndexDate"), 112)) AS "6MonthBeforeKey",
    CONVERT(int, CONVERT(char(8), DATEADD(month, 6, "IndexDate"), 112)) AS "6MonthAfterKey",
    CONVERT(int, CONVERT(char(8), DATEADD(day, 1, "IndexDate"), 112)) AS "1DayAfterKey",
    -- datetime
    CAST("IndexDate" AS datetime2) AS "IndexStartTS",
    CAST(DATEADD(day, 1, CAST("IndexDate" AS date)) AS datetime2) AS "IndexEndTS"
INTO #tmp_plan_window
FROM #tmp_plan_cohort
WHERE "IndexDate" IS NOT NULL
;

CREATE UNIQUE NONCLUSTERED INDEX UX_tmp_plan_window_PDKey_TPKey ON #tmp_plan_window ("PatientDurableKey", "TreatmentPlanKey");


DECLARE @sec1_end datetime2(3) = SYSDATETIME();
DECLARE @sec1_elapsed int = DATEDIFF(SECOND, @sec1_start, @sec1_end);
RAISERROR('Section 1 elapsed seconds: %d', 0, 1, @sec1_elapsed) WITH NOWAIT;


/*********************************************************************
** 2. Demographics & Provider
*********************************************************************/
DECLARE @sec2_start datetime2(3) = SYSDATETIME();

-- =====================================================
-- TEMP TABLE: demographics (long)
-- =====================================================
DROP TABLE IF EXISTS #tmp_demog_long;
SELECT
    cohort."PatientDurableKey",
    cohort."TreatmentPlanKey",
    cohort."IndexDate",
    pd."Name" AS "PatientName",
    pd."PrimaryMrn" AS "PatientMRN",
    pd."BirthDate",
    pd."Sex",
    pd."FirstRace",
    pd."SecondRace",
    pd."Ethnicity",
    pd."CountryOfOrigin",
    pd."PreferredLanguage",
    ROW_NUMBER() OVER (
        PARTITION BY cohort."PatientDurableKey", cohort."TreatmentPlanKey"
        ORDER BY pd."StartDate" DESC, pd."EndDate" DESC
    ) AS row_num
INTO #tmp_demog_long
FROM #tmp_plan_cohort cohort
INNER JOIN "PatientDim" pd
    ON cohort."PatientDurableKey" = pd."DurableKey"
        AND pd."StartDate" <= cohort."IndexDate"
        AND (pd."EndDate" IS NULL OR pd."EndDate" >= cohort."IndexDate")
;

CREATE UNIQUE NONCLUSTERED INDEX UX_tmp_demog_PDKey_TPKey ON #tmp_demog_long ("PatientDurableKey", "TreatmentPlanKey");


-- =====================================================
-- TEMP TABLE: demographics (wide)
-- =====================================================
DROP TABLE IF EXISTS #tmp_feat_demog;
SELECT
    demog."PatientDurableKey",
    demog."TreatmentPlanKey",
    "PatientName",
    "PatientMRN",
    CASE
        WHEN demog."BirthDate" IS NOT NULL AND demog."IndexDate" IS NOT NULL
            THEN DATEPART(year, demog."IndexDate")
                - DATEPART(year, demog."BirthDate")
    END AS "Age",
    demog."Sex",
    COALESCE(
        -- Use FirstRace
        CASE
            WHEN TRIM(UPPER(COALESCE(demog."FirstRace", ''))) = 'BLACK OR AFRICAN AMERICAN'
                THEN 'Black or African American'
            WHEN TRIM(UPPER(COALESCE(demog."FirstRace", ''))) = 'WHITE OR CAUCASIAN'
                THEN 'White'
            WHEN TRIM(UPPER(COALESCE(demog."FirstRace", ''))) = 'ASIAN'
                THEN 'Asian'
            WHEN TRIM(UPPER(COALESCE(demog."FirstRace", ''))) = 'AMERICAN INDIAN OR ALASKA NATIVE'
                THEN 'American Indian or Alaska Native'
            WHEN TRIM(UPPER(COALESCE(demog."FirstRace", ''))) LIKE '%PACIFIC ISLANDER%'
                THEN 'Native Hawaiian or Other Pacific Islander'
            ELSE NULL
        END,
        -- Use SecondRace
        CASE
            WHEN TRIM(UPPER(COALESCE(demog."SecondRace", ''))) = 'BLACK OR AFRICAN AMERICAN'
                THEN 'Black or African American'
            WHEN TRIM(UPPER(COALESCE(demog."SecondRace", ''))) = 'WHITE OR CAUCASIAN'
                THEN 'White'
            WHEN TRIM(UPPER(COALESCE(demog."SecondRace", ''))) = 'ASIAN'
                THEN 'Asian'
            WHEN TRIM(UPPER(COALESCE(demog."SecondRace", ''))) = 'AMERICAN INDIAN OR ALASKA NATIVE'
                THEN 'American Indian or Alaska Native'
            WHEN TRIM(UPPER(COALESCE(demog."SecondRace", ''))) LIKE '%PACIFIC ISLANDER%'
                THEN 'Native Hawaiian or Other Pacific Islander'
            ELSE NULL
        END,
        -- Use CountryOfOrigin
        cr.race,
        -- Use PreferredLanguage
        lr.race,
        -- Default
        'Other'
    ) AS "CleanRace",
    COALESCE(
        -- Hispanic
        CASE
            WHEN UPPER(TRIM(COALESCE(demog."Ethnicity", ''))) IN (
                'CUBAN',
                'HISPANIC/LATINO- ALL OTHER',
                'MEXICAN OR CHICANO',
                'OTHER HISPANIC, LATINO OR SPANISH ORIGIN',
                'PUERTO RICAN'
            )
            THEN 'hispanic'
        END,
        -- Non-hispanic
        CASE
            WHEN UPPER(TRIM(COALESCE(demog."Ethnicity", ''))) IN (
                'BLACK/AFRICAN AMERICAN',
                'NOT HISPANIC/LATINO'
            )
            THEN 'non-hispanic'
        END,
        -- Language -> race(Asian) -> non-hispanic
        CASE
            WHEN lr.race = 'Asian' THEN 'non-hispanic'
        END,
        -- Language(Spanish) -> hispanic
        CASE
            WHEN UPPER(TRIM(COALESCE(demog."PreferredLanguage", ''))) = 'SPANISH'
                THEN 'hispanic'
        END,
        -- Default
        'Unknown'
    ) AS "CleanEthnicity"
INTO #tmp_feat_demog
FROM #tmp_demog_long demog
LEFT JOIN #tmp_country_2_race cr
    ON cr.country = UPPER(TRIM(COALESCE(demog."CountryOfOrigin", '')))
LEFT JOIN #tmp_lang_2_race lr
    ON lr.language = UPPER(TRIM(COALESCE(demog."PreferredLanguage", '')))
WHERE demog.row_num = 1
;

CREATE UNIQUE NONCLUSTERED INDEX UX_tmp_feat_demog_PDKey_TPKey ON #tmp_feat_demog ("PatientDurableKey", "TreatmentPlanKey");


-- =====================================================
-- TEMP TABLE: provider (wide)
-- =====================================================
DROP TABLE IF EXISTS #tmp_feat_provider;
SELECT
    cohort."PatientDurableKey",
    cohort."TreatmentPlanKey",
    prov."Name" AS "ProviderName",
    prov."Email" AS "ProviderEmail",
    COALESCE(m.loc_cat, 'other') AS "ProviderLocation"
INTO #tmp_feat_provider
FROM #tmp_plan_cohort cohort
INNER JOIN "ProviderDim" prov
    ON cohort."PlanProviderDurableKey" = prov."DurableKey"
        AND prov."IsCurrent" = 1
LEFT JOIN #tmp_location_map m
    ON m.loc_name = UPPER(LTRIM(RTRIM(COALESCE(prov."PrimaryLocation", ''))))
;

CREATE UNIQUE NONCLUSTERED INDEX UX_tmp_feat_provider_PDKey_TPKey ON #tmp_feat_provider ("PatientDurableKey", "TreatmentPlanKey");


DECLARE @sec2_end datetime2(3) = SYSDATETIME();
DECLARE @sec2_elapsed int = DATEDIFF(SECOND, @sec2_start, @sec2_end);
RAISERROR('Section 2 elapsed seconds: %d', 0, 1, @sec2_elapsed) WITH NOWAIT;


/*********************************************************************
** 3. Diagnoses
*********************************************************************/
DECLARE @sec3_start datetime2(3) = SYSDATETIME();

-- =====================================================
-- TEMP TABLE: diagnoses (long)
-- =====================================================
DROP TABLE IF EXISTS #tmp_diagnoses_long;
WITH all_diagnoses AS (
    SELECT
        win."PatientDurableKey",
        win."TreatmentPlanKey",
        CAST('EVENT' AS VARCHAR(10)) AS "SourceType",
        devent."DiagnosisKey",
        devent."StartDateKey",
        devent."EndDateKey",
        dx."CancerType",
        dx."VTEType",
        dx."IsMetastatic",
        dx."IsParalysis"
    FROM #tmp_plan_window win
    INNER JOIN "DiagnosisEventFact" devent
        ON win."PatientDurableKey" = devent."PatientDurableKey"
            AND devent."Count" = 1
            AND devent."Type" IN ('Encounter Diagnosis', 'Billing Diagnosis')
            AND devent."StartDateKey" > 19000101
            -- we never need anything after 3 months from index
            AND devent."StartDateKey" <= win."3MonthAfterKey"
    INNER JOIN #tmp_classified_diagnosis dx
        ON devent."DiagnosisKey" = dx."DiagnosisKey"
            AND (
                dx."CancerType" IS NOT NULL
                OR dx."VTEType" IS NOT NULL
                OR dx."IsMetastatic" = 1
                OR dx."IsParalysis" = 1
            )
    UNION ALL
    SELECT
        win."PatientDurableKey",
        win."TreatmentPlanKey",
        CAST('COND' AS VARCHAR(10)) AS "SourceType",
        dcond."DiagnosisKey",
        dcond."StartDateKey",
        dcond."EndDateKey",
        dx."CancerType",
        dx."VTEType",
        dx."IsMetastatic",
        dx."IsParalysis"
    FROM #tmp_plan_window win
    INNER JOIN "DiagnosisEventFact" dcond
        ON win."PatientDurableKey" = dcond."PatientDurableKey"
            AND dcond."Count" = 1
            AND dcond."Type" IN ('Medical History', 'Problem List', 'Hospital Problem')
            AND dcond."StartDateKey" > 19000101
            -- we never need anything after 3 months from index
            AND dcond."StartDateKey" <= win."3MonthAfterKey"
            -- ongoing or finished condition
            AND (
                dcond."EndDateKey" IS NULL
                OR dcond."EndDateKey" < 19000101
                OR dcond."EndDateKey" >= win."IndexDateKey"
            )
    INNER JOIN #tmp_classified_diagnosis dx
        ON dcond."DiagnosisKey" = dx."DiagnosisKey"
            AND (
                dx."CancerType" IS NOT NULL
                OR dx."VTEType" IS NOT NULL
                OR dx."IsMetastatic" = 1
                OR dx."IsParalysis" = 1
            )
)
SELECT *
INTO #tmp_diagnoses_long
FROM all_diagnoses
;

CREATE NONCLUSTERED INDEX IX_tmp_diagnoses_long_PDKey_TPKey ON #tmp_diagnoses_long ("PatientDurableKey", "TreatmentPlanKey");
CREATE NONCLUSTERED INDEX IX_tmp_diagnoses_long_SDKey ON #tmp_diagnoses_long ("StartDateKey");
CREATE NONCLUSTERED INDEX IX_tmp_diagnoses_long_CType ON #tmp_diagnoses_long ("CancerType");
CREATE NONCLUSTERED INDEX IX_tmp_diagnoses_long_Met_Para ON #tmp_diagnoses_long ("IsMetastatic", "IsParalysis");


-- =====================================================
-- TEMP TABLE: cancer (wide)
-- =====================================================
DROP TABLE IF EXISTS #tmp_feat_cancer;
WITH counts AS (
    SELECT
        win."PatientDurableKey",
        win."TreatmentPlanKey",
        dx."CancerType",
        MIN(dx."StartDateKey") AS "StartDateKey",
        COUNT(*) AS cnt
    FROM #tmp_plan_window win
    INNER JOIN #tmp_diagnoses_long dx
        ON win."PatientDurableKey" = dx."PatientDurableKey"
            AND win."TreatmentPlanKey" = dx."TreatmentPlanKey"
            AND dx."CancerType" IS NOT NULL
            AND dx."StartDateKey" >= win."3MonthBeforeKey"
            AND dx."StartDateKey" <= win."3MonthAfterKey"
    GROUP BY win."PatientDurableKey", win."TreatmentPlanKey", dx."CancerType"
),
ranked AS (
    SELECT
        "PatientDurableKey",
        "TreatmentPlanKey",
        "CancerType",
        "StartDateKey",
        ROW_NUMBER() OVER (
            PARTITION BY "PatientDurableKey", "TreatmentPlanKey"
            ORDER BY cnt DESC, "StartDateKey" ASC, "CancerType" ASC
        ) AS row_num
    FROM counts
)
SELECT
    "PatientDurableKey",
    "TreatmentPlanKey",
    "CancerType"
INTO #tmp_feat_cancer
FROM ranked
WHERE row_num = 1
;

CREATE UNIQUE NONCLUSTERED INDEX UX_tmp_feat_cancer_PDKey_TPKey ON #tmp_feat_cancer ("PatientDurableKey", "TreatmentPlanKey");


-- =====================================================
-- TEMP TABLE: metastatic ICD (wide)
-- =====================================================
DROP TABLE IF EXISTS #tmp_feat_met_icd;
WITH ranked AS (
    SELECT
        win."PatientDurableKey",
        win."TreatmentPlanKey",
        MIN(dx."StartDateKey") AS "StartDateKey"
    FROM #tmp_plan_window win
    INNER JOIN #tmp_diagnoses_long dx
        ON win."PatientDurableKey" = dx."PatientDurableKey"
            AND win."TreatmentPlanKey" = dx."TreatmentPlanKey"
            AND dx."IsMetastatic" = 1
            AND dx."StartDateKey" >= win."3MonthBeforeKey"
            AND dx."StartDateKey" <= win."3MonthAfterKey"
    GROUP BY win."PatientDurableKey", win."TreatmentPlanKey"
)
SELECT
    win."PatientDurableKey",
    win."TreatmentPlanKey",
    CASE WHEN ranked."StartDateKey" IS NOT NULL THEN 1 ELSE 0 END AS "HasMetastaticICD",
    CASE WHEN ranked."StartDateKey" IS NOT NULL
        THEN TRY_CONVERT(date, TRY_CONVERT(char(8), ranked."StartDateKey"), 112)
    END AS "MetastaticICDDate"
INTO #tmp_feat_met_icd
FROM #tmp_plan_window win
LEFT JOIN ranked
    ON win."PatientDurableKey" = ranked."PatientDurableKey"
        AND win."TreatmentPlanKey" = ranked."TreatmentPlanKey"
;

CREATE UNIQUE NONCLUSTERED INDEX UX_tmp_feat_met_icd_PDKey_TPKey ON #tmp_feat_met_icd ("PatientDurableKey", "TreatmentPlanKey");


-- =====================================================
-- TEMP TABLE: VTE history (wide)
-- =====================================================
DROP TABLE IF EXISTS #tmp_feat_vte_hx;
WITH ranked AS (
    SELECT
        win."PatientDurableKey",
        win."TreatmentPlanKey",
        MAX(dx."StartDateKey") AS "StartDateKey"
    FROM #tmp_plan_window win
    INNER JOIN #tmp_diagnoses_long dx
        ON win."PatientDurableKey" = dx."PatientDurableKey"
            AND win."TreatmentPlanKey" = dx."TreatmentPlanKey"
            AND dx."VTEType" IS NOT NULL
            AND dx."StartDateKey" > 19000101
            AND dx."StartDateKey" <= win."IndexDateKey"
    GROUP BY win."PatientDurableKey", win."TreatmentPlanKey"
)
SELECT
    win."PatientDurableKey",
    win."TreatmentPlanKey",
    CASE WHEN ranked."StartDateKey" IS NOT NULL
        THEN TRY_CONVERT(date, TRY_CONVERT(char(8), ranked."StartDateKey"), 112)
    END AS "VteHxDate"
INTO #tmp_feat_vte_hx
FROM #tmp_plan_window win
LEFT JOIN ranked
    ON win."PatientDurableKey" = ranked."PatientDurableKey"
        AND win."TreatmentPlanKey" = ranked."TreatmentPlanKey"
;

CREATE UNIQUE NONCLUSTERED INDEX UX_tmp_feat_vte_hx_PDKey_TPKey ON #tmp_feat_vte_hx ("PatientDurableKey", "TreatmentPlanKey");


-- =====================================================
-- TEMP TABLE: paralysis history (wide)
-- =====================================================
DROP TABLE IF EXISTS #tmp_feat_paralysis_hx;
WITH ranked AS (
    SELECT
        win."PatientDurableKey",
        win."TreatmentPlanKey",
        MAX(dx."StartDateKey") AS "StartDateKey"
    FROM #tmp_plan_window win
    INNER JOIN #tmp_diagnoses_long dx
        ON win."PatientDurableKey" = dx."PatientDurableKey"
            AND win."TreatmentPlanKey" = dx."TreatmentPlanKey"
            AND dx."IsParalysis" = 1
            AND dx."StartDateKey" > 19000101
            AND dx."StartDateKey" >= win."12MonthBeforeKey"
            AND dx."StartDateKey" <= win."IndexDateKey"
    GROUP BY win."PatientDurableKey", win."TreatmentPlanKey"
)
SELECT
    win."PatientDurableKey",
    win."TreatmentPlanKey",
    CASE WHEN ranked."StartDateKey" IS NOT NULL
        THEN TRY_CONVERT(date, TRY_CONVERT(char(8), ranked."StartDateKey"), 112)
    END AS "ParalysisHxDate"
INTO #tmp_feat_paralysis_hx
FROM #tmp_plan_window win
LEFT JOIN ranked
    ON win."PatientDurableKey" = ranked."PatientDurableKey"
        AND win."TreatmentPlanKey" = ranked."TreatmentPlanKey"
;

CREATE UNIQUE NONCLUSTERED INDEX UX_tmp_feat_paralysis_hx_PDKey_TPKey ON #tmp_feat_paralysis_hx ("PatientDurableKey", "TreatmentPlanKey");


DECLARE @sec3_end datetime2(3) = SYSDATETIME();
DECLARE @sec3_elapsed int = DATEDIFF(SECOND, @sec3_start, @sec3_end);
RAISERROR('Section 3 elapsed seconds: %d', 0, 1, @sec3_elapsed) WITH NOWAIT;


/*********************************************************************
** 4. Labs
*********************************************************************/
DECLARE @sec4_start datetime2(3) = SYSDATETIME();

-- =====================================================
-- TEMP TABLE: labs (long)
-- =====================================================
DROP TABLE IF EXISTS #tmp_labs_long;
SELECT
    win."PatientDurableKey",
    win."TreatmentPlanKey",
    lab."NumericValue",
    lab."CollectionInstant",
    lab."LabComponentResultKey",
    lt."LabType",
    ROW_NUMBER() OVER (
        PARTITION BY win."PatientDurableKey", win."TreatmentPlanKey", lt."LabType"
        ORDER BY lab."CollectionInstant" DESC, lab."LabComponentResultKey" DESC
    ) AS row_num
INTO #tmp_labs_long
FROM #tmp_plan_window win
INNER JOIN "LabComponentResultFact" lab
    ON win."PatientDurableKey" = lab."PatientDurableKey"
        AND lab."Count" = 1
        AND lab."PrioritizedDateKey" >= win."3MonthBeforeKey"
        AND lab."PrioritizedDateKey" < win."IndexDateKey"
INNER JOIN "LabComponentDim" ldim
    ON lab."LabComponentKey" = ldim."LabComponentKey"
INNER JOIN "ProcedureDim" lproc
    ON lab."ProcedureKey" = lproc."ProcedureKey"
CROSS APPLY (
    VALUES (
        CASE
            WHEN ldim."LoincCode" IN ('777-3', '778-1', '13056-7', '26515-7', '26516-5', '49497-1', '74775-8', '74464-9', '97995-5')
                OR (
                    (UPPER(lproc."Name") LIKE 'CBC%' OR UPPER(lproc."Name") = 'PLATELET')
                    AND (UPPER(ldim."CommonName") IN ('PLATELET','PLATELETS') OR UPPER(ldim."CommonName") LIKE 'PLT%')
                )
            THEN 'PLT'
            WHEN ldim."LoincCode" IN ('804-5', '6690-2', '12227-5', '26464-8', '33256-9', '49498-9')
                OR (
                    UPPER(lproc."Name") LIKE 'CBC%'
                    AND (UPPER(ldim."CommonName") = 'WHITE BLOOD CELL COUNT' OR UPPER(ldim."CommonName") LIKE 'WBC%')
                )
            THEN 'WBC'
            WHEN ldim."LoincCode" IN ('718-7', '14775-1', '20509-6', '30313-1', '30350-3', '30351-1', '30352-9', '55782-7', '76768-1', '76769-9', '97556-5', '97550-8', '97555-7')
                OR (
                    UPPER(lproc."Name") LIKE 'CBC%'
                    AND (UPPER(ldim."CommonName") = 'HEMOGLOBIN' OR UPPER(ldim."CommonName") LIKE 'HGB%')
                )
            THEN 'HGB'
            WHEN ldim."LoincCode" IN ('1742-6', '1743-4', '1744-2', '76625-3', '77144-4')
                OR (
                    (
                        UPPER(lproc."Name") IN ('COMPREHENSIVE METABOLIC PANEL', 'LIVER PROFILE', 'HEPATIC FUNCTION PANEL', 'ALT')
                        OR UPPER(lproc."Name") LIKE 'ALANINE AMINOTRA%'
                    )
                    AND UPPER(ldim."CommonName") = 'ALT'
                )
            THEN 'ALT'
            WHEN ldim."LoincCode" IN ('1920-8', '30239-8', '88112-8')
                OR (
                    UPPER(lproc."Name") IN ('COMPREHENSIVE METABOLIC PANEL', 'LIVER PROFILE', 'HEPATIC FUNCTION PANEL', 'AST')
                    AND UPPER(ldim."CommonName") = 'AST'
                )
            THEN 'AST'
            WHEN ldim."LoincCode" IN ('2160-0', '21232-4', '35203-9', '38483-4')
                OR (
                    UPPER(lproc."Name") IN ('COMPREHENSIVE METABOLIC PANEL', 'BASIC METABOLIC PANEL')
                    AND UPPER(ldim."CommonName") IN ('CREATININE', 'CR')
                )
            THEN 'CR'
            ELSE NULL
        END
    )
) AS lt("LabType")
WHERE lt."LabType" IS NOT NULL
;

CREATE NONCLUSTERED INDEX IX_tmp_labs_long_PDKey_TPKey ON #tmp_labs_long ("PatientDurableKey", "TreatmentPlanKey");
CREATE NONCLUSTERED INDEX IX_tmp_labs_long_LType ON #tmp_labs_long ("LabType");


-- =====================================================
-- TEMP TABLE: labs (wide)
-- =====================================================
DROP TABLE IF EXISTS #tmp_feat_labs;
SELECT
    "PatientDurableKey",
    "TreatmentPlanKey",
    MAX(CASE WHEN "LabType" = 'PLT' AND row_num = 1 THEN "NumericValue" END) AS "PltValue",
    MAX(CASE WHEN "LabType" = 'PLT' AND row_num = 1 THEN "CollectionInstant" END) AS "PltInstant",
    MAX(CASE WHEN "LabType" = 'WBC' AND row_num = 1 THEN "NumericValue" END) AS "WBCValue",
    MAX(CASE WHEN "LabType" = 'WBC' AND row_num = 1 THEN "CollectionInstant" END) AS "WBCInstant",
    MAX(CASE WHEN "LabType" = 'HGB' AND row_num = 1 THEN "NumericValue" END) AS "HgbValue",
    MAX(CASE WHEN "LabType" = 'HGB' AND row_num = 1 THEN "CollectionInstant" END) AS "HgbInstant",
    MAX(CASE WHEN "LabType" = 'ALT' AND row_num = 1 THEN "NumericValue" END) AS "ALTValue",
    MAX(CASE WHEN "LabType" = 'ALT' AND row_num = 1 THEN "CollectionInstant" END) AS "ALTInstant",
    MAX(CASE WHEN "LabType" = 'AST' AND row_num = 1 THEN "NumericValue" END) AS "ASTValue",
    MAX(CASE WHEN "LabType" = 'AST' AND row_num = 1 THEN "CollectionInstant" END) AS "ASTInstant",
    MAX(CASE WHEN "LabType" = 'CR' AND row_num = 1 THEN "NumericValue" END) AS "CrValue",
    MAX(CASE WHEN "LabType" = 'CR' AND row_num = 1 THEN "CollectionInstant" END) AS "CrInstant"
INTO #tmp_feat_labs
FROM #tmp_labs_long
WHERE "LabType" IS NOT NULL
GROUP BY "PatientDurableKey", "TreatmentPlanKey"
;

CREATE UNIQUE NONCLUSTERED INDEX UX_tmp_feat_labs_PDKey_TPKey ON #tmp_feat_labs ("PatientDurableKey", "TreatmentPlanKey");


DECLARE @sec4_end datetime2(3) = SYSDATETIME();
DECLARE @sec4_elapsed int = DATEDIFF(SECOND, @sec4_start, @sec4_end);
RAISERROR('Section 4 elapsed seconds: %d', 0, 1, @sec4_elapsed) WITH NOWAIT;


/*********************************************************************
** 5. Vitals
*********************************************************************/
DECLARE @sec5_start datetime2(3) = SYSDATETIME();

-- =====================================================
-- TEMP TABLE: vitals (long)
-- =====================================================
DROP TABLE IF EXISTS #tmp_vitals_long;
SELECT
    win."PatientDurableKey",
    win."TreatmentPlanKey",
    UPPER(vdim."ValueType") AS "ValueType",
    vital."TakenInstant",
    vital."FlowsheetValueKey",
    CASE
        WHEN UPPER(vdim."ValueType") = 'PATIENT WEIGHT'
        THEN vital."NumericValue" * 0.028349523
    END AS "ValueKg",
    CASE WHEN UPPER(vdim."ValueType") = 'PATIENT HEIGHT'
        THEN vital."NumericValue" * 2.54
    END AS "ValueCm",
    ROW_NUMBER() OVER (
        PARTITION BY win."PatientDurableKey", win."TreatmentPlanKey",
            CASE
                WHEN UPPER(vdim."ValueType") IN ('PATIENT WEIGHT', 'PATIENT HEIGHT')
                THEN UPPER(vdim."ValueType")
            END
        ORDER BY vital."TakenInstant" DESC, vital."FlowsheetValueKey" DESC
    ) AS row_num
INTO #tmp_vitals_long
FROM #tmp_plan_window win
INNER JOIN "FlowsheetValueFact" vital
    ON win."PatientDurableKey" = vital."PatientDurableKey"
        AND vital."Count" = 1
        AND vital."DateKey" >= win."12MonthBeforeKey"
        AND vital."DateKey" < win."IndexDateKey"
INNER JOIN "FlowsheetRowDim" vdim
    ON vital."FlowsheetRowKey" = vdim."FlowsheetRowKey" 
        AND UPPER(vdim."ValueType") IN ('PATIENT WEIGHT', 'PATIENT HEIGHT')
;

CREATE NONCLUSTERED INDEX IX_tmp_vitals_long_PDKey_TPKey ON #tmp_vitals_long ("PatientDurableKey", "TreatmentPlanKey");


-- =====================================================
-- TEMP TABLE: vitals (wide)
-- =====================================================
DROP TABLE IF EXISTS #tmp_feat_vitals;
SELECT
    "PatientDurableKey",
    "TreatmentPlanKey",
    ROUND(MAX(CASE WHEN "ValueType" = 'PATIENT WEIGHT' AND row_num = 1 THEN "ValueKg" END), 2) AS "WeightKg",
    MAX(CASE WHEN "ValueType" = 'PATIENT WEIGHT' AND row_num = 1 THEN "TakenInstant" END) AS "WeightInstant",
    ROUND(MAX(CASE WHEN "ValueType" = 'PATIENT HEIGHT' AND row_num = 1 THEN "ValueCm" END), 2) AS "HeightCm",
    MAX(CASE WHEN "ValueType" = 'PATIENT HEIGHT' AND row_num = 1 THEN "TakenInstant" END) AS "HeightInstant",
    CASE
        WHEN MAX(CASE WHEN "ValueType" = 'PATIENT HEIGHT' AND row_num = 1 THEN "ValueCm" END) IS NOT NULL
            AND MAX(CASE WHEN "ValueType" = 'PATIENT HEIGHT' AND row_num = 1 THEN "ValueCm" END) <> 0
            AND MAX(CASE WHEN "ValueType" = 'PATIENT WEIGHT' AND row_num = 1 THEN "ValueKg" END) IS NOT NULL
        THEN
            ROUND(
                MAX(CASE WHEN "ValueType" = 'PATIENT WEIGHT' AND row_num = 1 THEN "ValueKg" END)
                / POWER(
                    MAX(CASE WHEN "ValueType" = 'PATIENT HEIGHT' AND row_num = 1 THEN "ValueCm" END) / 100.0,
                    2
                ),
                2
            )
    END AS "BMI"
INTO #tmp_feat_vitals
FROM #tmp_vitals_long
GROUP BY "PatientDurableKey", "TreatmentPlanKey"
;

CREATE UNIQUE NONCLUSTERED INDEX UX_tmp_feat_vitals_PDKey_TPKey ON #tmp_feat_vitals ("PatientDurableKey", "TreatmentPlanKey");


DECLARE @sec5_end datetime2(3) = SYSDATETIME();
DECLARE @sec5_elapsed int = DATEDIFF(SECOND, @sec5_start, @sec5_end);
RAISERROR('Section 5 elapsed seconds: %d', 0, 1, @sec5_elapsed) WITH NOWAIT;


/*********************************************************************
** 6. Medications
*********************************************************************/
DECLARE @sec6_start datetime2(3) = SYSDATETIME();

-- =====================================================
-- TEMP TABLE: IP medications (long)
-- =====================================================
DROP TABLE IF EXISTS #tmp_ip_meds_long;
SELECT
    win."PatientDurableKey",
    win."TreatmentPlanKey",
    maf."AdministrationDateKey",
    maf."AdministrationInstant",
    cm."Name",
    cm."SimpleGenericName",
    cm."isAC",
    cm."isContraind",
    cm."isStatin"
INTO #tmp_ip_meds_long
FROM #tmp_plan_window win
INNER JOIN "HospitalAdmissionFact" haf
    ON win."PatientDurableKey" = haf."PatientDurableKey"
        AND haf."Count" = 1
        AND haf."AdmissionDateKey" > 19000101
        AND haf."AdmissionDateKey" <= win."IndexDateKey"
        AND (
            haf."DischargeDateKey" IS NULL
            OR haf."DischargeDateKey" >= win."IndexDateKey"
        )
INNER JOIN "MedicationAdministrationFact" maf 
    ON win."PatientDurableKey" = maf."PatientDurableKey" 
        AND maf."Count" = 1
        AND (
            UPPER(maf."AdministrationAction") IN ('BOLUS', 'PUSH', 'RESTARTED', 'IV RESUME', 'PATCH APPLIED', 'PATIENT/FAMILY ADMIN')
            OR UPPER(maf."AdministrationAction") LIKE 'GIVEN%'
            OR UPPER(maf."AdministrationAction") LIKE 'NEW%'
        )
        -- administration date between hosp admission and discharge or administration date on index date
        AND (
            ( 
                maf."AdministrationDateKey" >= haf."AdmissionDateKey"
                AND maf."AdministrationDateKey" <= COALESCE(haf."DischargeDateKey", TRY_CONVERT(int, TRY_CONVERT(char(8), GETDATE(), 112)))
            )
            OR maf."AdministrationDateKey" = win."IndexDateKey"
        )
INNER JOIN "MedicationOrderComponentFact" mocf
    ON maf."MedicationOrderKey" = mocf."MedicationOrderKey"
        AND mocf."Count" = 1
INNER JOIN #tmp_classified_meds cm
    ON mocf."MedicationKey" = cm."MedicationKey"
        AND (
            (
                cm."isAC" = 1 
                AND (
                    (
                        UPPER(cm."PharmaceuticalSubclass") = 'HEPARINS'
                        AND UPPER(maf."DoseUnit") IN ('UNITS/HR', 'UNITS/KG/HR') --, 'ML/HR', 'UNITS/KG')
                    )
                    OR (
                        UPPER(cm."PharmaceuticalSubclass") = 'LOW MOLECULAR WEIGHT HEPARINS'
                        AND NOT (UPPER(cm."Strength") LIKE '30 MG%' OR UPPER(cm."Strength") LIKE '40 MG%')
                    )
                    OR (
                        UPPER(cm."PharmaceuticalSubclass") NOT IN ('HEPARINS', 'LOW MOLECULAR WEIGHT HEPARINS')
                    )
                )
            )
            OR cm."isContraind" = 1
            OR cm."isStatin" = 1
        )
;

CREATE NONCLUSTERED INDEX IX_tmp_ip_meds_long_PDKey_TPKey ON #tmp_ip_meds_long ("PatientDurableKey", "TreatmentPlanKey");


-- =====================================================
-- TEMP TABLE: OP medications (long)
-- =====================================================
DROP TABLE IF EXISTS #tmp_op_meds_long;
SELECT
    win."PatientDurableKey",
    win."TreatmentPlanKey",
    mof."StartDateKey" AS "OrderStartDateKey",
    mof."EndDateKey" AS "OrderEndDateKey",
    mof."DiscontinuedLocalDateKey" AS "OrderDiscontinuedDateKey",
    cm."Name",
    cm."SimpleGenericName",
    cm."isAC",
    cm."isContraind",
    cm."isStatin"
INTO #tmp_op_meds_long
FROM #tmp_plan_window win
INNER JOIN "MedicationOrderFact" mof 
    ON win."PatientDurableKey" = mof."PatientDurableKey" 
        AND mof."Count" = 1
        -- start date or order date <= index date
        AND ( 
            mof."StartDateKey" <= win."IndexDateKey" 
            OR mof."OrderedDateKey" <= win."IndexDateKey" 
        )
        -- end date null or >= index date
        AND (
            mof."EndDateKey" IS NULL 
            OR mof."EndDateKey" < 19000101
            OR mof."EndDateKey" >= win."IndexDateKey"
        )
        -- discontinued date null or >= index date
        AND (
            mof."DiscontinuedLocalDateKey" IS NULL 
            OR mof."DiscontinuedLocalDateKey" < 19000101
            OR mof."DiscontinuedLocalDateKey" >= win."IndexDateKey"
        )        
        AND UPPER(mof."Mode") = 'OUTPATIENT'
        AND (
            mof."IsPending" IS NULL
            OR mof."IsPending" <> 1
        )
INNER JOIN "MedicationOrderComponentFact" mocf
    ON mof."MedicationOrderKey" = mocf."MedicationOrderKey"
        AND mocf."Count" = 1
INNER JOIN #tmp_classified_meds cm
    ON mocf."MedicationKey" = cm."MedicationKey"
        AND (
            (cm."isAC" = 1 AND UPPER(cm."PharmaceuticalSubclass") <> 'HEPARINS')
            OR cm."isContraind" = 1
            OR cm."isStatin" = 1
        )
;

CREATE NONCLUSTERED INDEX IX_tmp_op_meds_long_PDKey_TPKey ON #tmp_op_meds_long ("PatientDurableKey", "TreatmentPlanKey");


-- =====================================================
-- TEMP TABLE: Reported medications (long)
-- =====================================================
DROP TABLE IF EXISTS #tmp_reported_meds_long;
SELECT
    win."PatientDurableKey",
    win."TreatmentPlanKey",
    mef."StartDateKey" AS "EventStartDateKey",
    mef."EndDateKey" AS "EventEndDateKey",
    cm."Name",
    cm."SimpleGenericName",
    cm."isAC",
    cm."isContraind",
    cm."isStatin"
INTO #tmp_reported_meds_long
FROM #tmp_plan_window win
INNER JOIN "MedicationEventFact" mef 
    ON win."PatientDurableKey" = mef."PatientDurableKey" 
        AND mef."Count" = 1
        -- start date <= index date
        AND mef."StartDateKey" <= win."IndexDateKey" 
        -- end date null or >= index date
        AND (
            mef."EndDateKey" IS NULL 
            OR mef."EndDateKey" < 19000101
            OR mef."EndDateKey" >= win."IndexDateKey"
        )
        AND (mef."MedicationOrderKey" IS NULL OR mef."MedicationOrderKey" < 0)
INNER JOIN #tmp_classified_meds cm
    ON mef."MedicationKey" = cm."MedicationKey"
        AND (
            (cm."isAC" = 1 AND UPPER(cm."PharmaceuticalSubclass") <> 'HEPARINS')
            OR cm."isContraind" = 1
            OR cm."isStatin" = 1
        )
;

CREATE NONCLUSTERED INDEX IX_tmp_reported_meds_long_PDKey_TPKey ON #tmp_reported_meds_long ("PatientDurableKey", "TreatmentPlanKey");


-- =====================================================
-- TEMP TABLE: IP medications (wide)
-- =====================================================
DROP TABLE IF EXISTS #tmp_feat_ip_meds;
WITH base AS (
    SELECT
        "PatientDurableKey",
        "TreatmentPlanKey",
        -- AC
        COALESCE(SUM(CASE WHEN "isAC" = 1 THEN 1 ELSE 0 END), 0) AS "IpAcCnt",
        MAX(
            CASE
                WHEN "isAC" = 1
                THEN TRY_CONVERT(date, TRY_CONVERT(char(8), "AdministrationDateKey"), 112)
            END
        ) AS "IpAcDate",
        -- Contraind
        COALESCE(SUM(CASE WHEN "isContraind" = 1 THEN 1 ELSE 0 END), 0) AS "IpContraindCnt",
        MAX(
            CASE
                WHEN "isContraind" = 1
                THEN TRY_CONVERT(date, TRY_CONVERT(char(8), "AdministrationDateKey"), 112)
            END
        ) AS "IpContraindDate",
        -- Statin
        COALESCE(SUM(CASE WHEN "isStatin" = 1 THEN 1 ELSE 0 END), 0) AS "IpStatinCnt",
        MAX(
            CASE
                WHEN "isStatin" = 1
                THEN TRY_CONVERT(date, TRY_CONVERT(char(8), "AdministrationDateKey"), 112)
            END
        ) AS "IpStatinDate"
    FROM #tmp_ip_meds_long
    GROUP BY "PatientDurableKey", "TreatmentPlanKey"
),
distinct_sgn AS (
    SELECT DISTINCT
        "PatientDurableKey",
        "TreatmentPlanKey",
        CAST("SimpleGenericName" AS nvarchar(max)) AS "SimpleGenericName",
        "isAC",
        "isContraind",
        "isStatin"
    FROM #tmp_ip_meds_long
    WHERE "SimpleGenericName" IS NOT NULL AND "SimpleGenericName" <> ''
),
agg_sgn AS (
    SELECT
        "PatientDurableKey",
        "TreatmentPlanKey",
        -- AC
        STRING_AGG(
            CASE WHEN "isAC" = 1 THEN "SimpleGenericName" END,
            ','
        ) WITHIN GROUP (
            ORDER BY "SimpleGenericName"
        ) AS "IpAcSGN",
        -- Contraind
        STRING_AGG(
            CASE WHEN "isContraind" = 1 THEN "SimpleGenericName" END,
            ','
        ) WITHIN GROUP (
            ORDER BY "SimpleGenericName"
        ) AS "IpContraindSGN",
        -- Statin
        STRING_AGG(
            CASE WHEN "isStatin" = 1 THEN "SimpleGenericName" END,
            ','
        ) WITHIN GROUP (
            ORDER BY "SimpleGenericName"
        ) AS "IpStatinSGN"
    FROM distinct_sgn
    GROUP BY "PatientDurableKey", "TreatmentPlanKey"
)
SELECT
    base."PatientDurableKey",
    base."TreatmentPlanKey",
    base."IpAcCnt",
    base."IpAcDate",
    agg_sgn."IpAcSGN",
    base."IpContraindCnt",
    base."IpContraindDate",
    agg_sgn."IpContraindSGN",
    base."IpStatinCnt",
    base."IpStatinDate",
    agg_sgn."IpStatinSGN"
INTO #tmp_feat_ip_meds
FROM base
LEFT JOIN agg_sgn
    ON base."PatientDurableKey" = agg_sgn."PatientDurableKey"
        AND base."TreatmentPlanKey" = agg_sgn."TreatmentPlanKey"
;

CREATE UNIQUE NONCLUSTERED INDEX UX_tmp_feat_ip_meds_PDKey_TPKey ON #tmp_feat_ip_meds ("PatientDurableKey", "TreatmentPlanKey");


-- =====================================================
-- TEMP TABLE: OP medications (wide)
-- =====================================================
DROP TABLE IF EXISTS #tmp_feat_op_meds;
WITH base AS (
    SELECT
        "PatientDurableKey",
        "TreatmentPlanKey",
        -- AC
        COALESCE(SUM(CASE WHEN "isAC" = 1 THEN 1 ELSE 0 END), 0) AS "OpAcCnt",
        MAX(
            CASE
                WHEN "isAC" = 1
                THEN TRY_CONVERT(date, TRY_CONVERT(char(8), "OrderStartDateKey"), 112)
            END
        ) AS "OpAcDate",
        -- Contraind
        COALESCE(SUM(CASE WHEN "isContraind" = 1 THEN 1 ELSE 0 END), 0) AS "OpContraindCnt",
        MAX(
            CASE
                WHEN "isContraind" = 1
                THEN TRY_CONVERT(date, TRY_CONVERT(char(8), "OrderStartDateKey"), 112)
            END
        ) AS "OpContraindDate",
        -- Statin
        COALESCE(SUM(CASE WHEN "isStatin" = 1 THEN 1 ELSE 0 END), 0) AS "OpStatinCnt",
        MAX(
            CASE
                WHEN "isStatin" = 1
                THEN TRY_CONVERT(date, TRY_CONVERT(char(8), "OrderStartDateKey"), 112)
            END
        ) AS "OpStatinDate"
    FROM #tmp_op_meds_long
    GROUP BY "PatientDurableKey", "TreatmentPlanKey"
),
distinct_sgn AS (
    SELECT DISTINCT
        "PatientDurableKey",
        "TreatmentPlanKey",
        CAST("SimpleGenericName" AS nvarchar(max)) AS "SimpleGenericName",
        "isAC",
        "isContraind",
        "isStatin"
    FROM #tmp_op_meds_long
    WHERE "SimpleGenericName" IS NOT NULL AND "SimpleGenericName" <> ''
),
agg_sgn AS (
    SELECT
        "PatientDurableKey",
        "TreatmentPlanKey",
        -- AC
        STRING_AGG(
            CASE WHEN "isAC" = 1 THEN "SimpleGenericName" END,
            ','
        ) WITHIN GROUP (
            ORDER BY "SimpleGenericName"
        ) AS "OpAcSGN",
        -- Contraind
        STRING_AGG(
            CASE WHEN "isContraind" = 1 THEN "SimpleGenericName" END,
            ','
        ) WITHIN GROUP (
            ORDER BY "SimpleGenericName"
        ) AS "OpContraindSGN",
        -- Statin
        STRING_AGG(
            CASE WHEN "isStatin" = 1 THEN "SimpleGenericName" END,
            ','
        ) WITHIN GROUP (
            ORDER BY "SimpleGenericName"
        ) AS "OpStatinSGN"
    FROM distinct_sgn
    GROUP BY "PatientDurableKey", "TreatmentPlanKey"
)
SELECT
    base."PatientDurableKey",
    base."TreatmentPlanKey",
    base."OpAcCnt",
    base."OpAcDate",
    agg_sgn."OpAcSGN",
    base."OpContraindCnt",
    base."OpContraindDate",
    agg_sgn."OpContraindSGN",
    base."OpStatinCnt",
    base."OpStatinDate",
    agg_sgn."OpStatinSGN"
INTO #tmp_feat_op_meds
FROM base
LEFT JOIN agg_sgn
    ON base."PatientDurableKey" = agg_sgn."PatientDurableKey"
        AND base."TreatmentPlanKey" = agg_sgn."TreatmentPlanKey"
;

CREATE UNIQUE NONCLUSTERED INDEX UX_tmp_feat_op_meds_PDKey_TPKey ON #tmp_feat_op_meds ("PatientDurableKey", "TreatmentPlanKey");


-- =====================================================
-- TEMP TABLE: Reported medications (wide)
-- =====================================================
DROP TABLE IF EXISTS #tmp_feat_reported_meds;
WITH base AS (
    SELECT
        "PatientDurableKey",
        "TreatmentPlanKey",
        -- AC
        COALESCE(SUM(CASE WHEN "isAC" = 1 THEN 1 ELSE 0 END), 0) AS "ReportedAcCnt",
        MAX(
            CASE
                WHEN "isAC" = 1
                THEN TRY_CONVERT(date, TRY_CONVERT(char(8), "EventStartDateKey"), 112)
            END
        ) AS "ReportedAcDate",
        -- Contraind
        COALESCE(SUM(CASE WHEN "isContraind" = 1 THEN 1 ELSE 0 END), 0) AS "ReportedContraindCnt",
        MAX(
            CASE
                WHEN "isContraind" = 1
                THEN TRY_CONVERT(date, TRY_CONVERT(char(8), "EventStartDateKey"), 112)
            END
        ) AS "ReportedContraindDate",
        -- Statin
        COALESCE(SUM(CASE WHEN "isStatin" = 1 THEN 1 ELSE 0 END), 0) AS "ReportedStatinCnt",
        MAX(
            CASE
                WHEN "isStatin" = 1
                THEN TRY_CONVERT(date, TRY_CONVERT(char(8), "EventStartDateKey"), 112)
            END
        ) AS "ReportedStatinDate"
    FROM #tmp_reported_meds_long
    GROUP BY "PatientDurableKey", "TreatmentPlanKey"
),
distinct_sgn AS (
    SELECT DISTINCT
        "PatientDurableKey",
        "TreatmentPlanKey",
        CAST("SimpleGenericName" AS nvarchar(max)) AS "SimpleGenericName",
        "isAC",
        "isContraind",
        "isStatin"
    FROM #tmp_reported_meds_long
    WHERE "SimpleGenericName" IS NOT NULL AND "SimpleGenericName" <> ''
),
agg_sgn AS (
    SELECT
        "PatientDurableKey",
        "TreatmentPlanKey",
        -- AC
        STRING_AGG(
            CASE WHEN "isAC" = 1 THEN "SimpleGenericName" END,
            ','
        ) WITHIN GROUP (
            ORDER BY "SimpleGenericName"
        ) AS "ReportedAcSGN",
        -- Contraind
        STRING_AGG(
            CASE WHEN "isContraind" = 1 THEN "SimpleGenericName" END,
            ','
        ) WITHIN GROUP (
            ORDER BY "SimpleGenericName"
        ) AS "ReportedContraindSGN",
        -- Statin
        STRING_AGG(
            CASE WHEN "isStatin" = 1 THEN "SimpleGenericName" END,
            ','
        ) WITHIN GROUP (
            ORDER BY "SimpleGenericName"
        ) AS "ReportedStatinSGN"
    FROM distinct_sgn
    GROUP BY "PatientDurableKey", "TreatmentPlanKey"
)
SELECT
    base."PatientDurableKey",
    base."TreatmentPlanKey",
    base."ReportedAcCnt",
    base."ReportedAcDate",
    agg_sgn."ReportedAcSGN",
    base."ReportedContraindCnt",
    base."ReportedContraindDate",
    agg_sgn."ReportedContraindSGN",
    base."ReportedStatinCnt",
    base."ReportedStatinDate",
    agg_sgn."ReportedStatinSGN"
INTO #tmp_feat_reported_meds
FROM base
LEFT JOIN agg_sgn
    ON base."PatientDurableKey" = agg_sgn."PatientDurableKey"
        AND base."TreatmentPlanKey" = agg_sgn."TreatmentPlanKey"
;

CREATE UNIQUE NONCLUSTERED INDEX UX_tmp_feat_reported_meds_PDKey_TPKey ON #tmp_feat_reported_meds ("PatientDurableKey", "TreatmentPlanKey");


DECLARE @sec6_end datetime2(3) = SYSDATETIME();
DECLARE @sec6_elapsed int = DATEDIFF(SECOND, @sec6_start, @sec6_end);
RAISERROR('Section 6 elapsed seconds: %d', 0, 1, @sec6_elapsed) WITH NOWAIT;


/*********************************************************************
** 7. Visits and hospitalizations
*********************************************************************/
DECLARE @sec7_start datetime2(3) = SYSDATETIME();

-- =====================================================
-- TEMP TABLE: past/future onc/infusion visits (long)
-- =====================================================
DROP TABLE IF EXISTS #tmp_visits_long;
SELECT
    win."PatientDurableKey",
    win."TreatmentPlanKey",
    ef."DateKey" AS "StartDateKey",
    CASE
        WHEN ef."DateKey" > win."DataPullDateKey" THEN 1 ELSE 0
    END AS "isFuture",
    CASE
        WHEN dd."DepartmentName" LIKE '%INFUSION%' THEN 'infusion'
        WHEN (dd."DepartmentName" LIKE '%ONC%' OR dd."DepartmentName" LIKE '%HEM%')
            AND dd."DepartmentName" NOT LIKE '%CONCIERGE%' THEN 'hemeonc'
    END AS "deptType"
INTO #tmp_visits_long
FROM #tmp_plan_window win
INNER JOIN "EncounterFact" ef
    ON win."PatientDurableKey" = ef."PatientDurableKey"
        AND ef."Count" = 1
        -- we don't really want data out of this window
        AND ef."DateKey" >= win."12MonthBeforeKey"
        AND ef."DateKey" <= win."3MonthAfterKey"
        AND ef."Type" IN ('Appointment', 'Infusion', 'Office Visit')
        AND ef."DerivedEncounterStatus" IN ('Complete', 'Possible')
INNER JOIN "DepartmentDim" dd 
    ON ef."DepartmentKey" = dd."DepartmentKey"
        AND dd."ServiceAreaEpicId" = '10'
        AND (
            (dd."DepartmentName" LIKE '%ONC%' OR dd."DepartmentName" LIKE '%HEM%' OR dd."DepartmentName" LIKE '%INFUSION%')
            AND dd."DepartmentName" NOT LIKE '%CONCIERGE%'
        )
;

CREATE NONCLUSTERED INDEX IX_tmp_visits_long_PDKey_TPKey ON #tmp_visits_long ("PatientDurableKey", "TreatmentPlanKey");


-- =====================================================
-- TEMP TABLE: visits (wide)
-- =====================================================
DROP TABLE IF EXISTS #tmp_feat_visits;
SELECT
    "PatientDurableKey",
    "TreatmentPlanKey",
    MAX(
        CASE
            WHEN "deptType" = 'infusion' AND "isFuture" = 0
            THEN TRY_CONVERT(date, TRY_CONVERT(char(8), "StartDateKey"), 112)
        END
    ) AS "LastInfusionDate",
    MIN(
        CASE
            WHEN "deptType" = 'infusion' AND "isFuture" = 1
            THEN TRY_CONVERT(date, TRY_CONVERT(char(8), "StartDateKey"), 112)
        END
    ) AS "PlannedInfusionDate",
    MAX(
        CASE
            WHEN "deptType" = 'hemeonc' AND "isFuture" = 0
            THEN TRY_CONVERT(date, TRY_CONVERT(char(8), "StartDateKey"), 112)
        END
    ) AS "LastOncDate",
    MIN(
        CASE
            WHEN "deptType" = 'hemeonc' AND "isFuture" = 1
            THEN TRY_CONVERT(date, TRY_CONVERT(char(8), "StartDateKey"), 112)
        END
    ) AS "PlannedOncDate"
INTO #tmp_feat_visits
FROM #tmp_visits_long
GROUP BY "PatientDurableKey", "TreatmentPlanKey"
;

CREATE UNIQUE NONCLUSTERED INDEX UX_tmp_feat_visits_PDKey_TPKey ON #tmp_feat_visits ("PatientDurableKey", "TreatmentPlanKey");


-- =====================================================
-- TEMP TABLE: hospitalizations (wide)
-- =====================================================
DROP TABLE IF EXISTS #tmp_feat_hosp_hx;
SELECT
    win."PatientDurableKey",
    win."TreatmentPlanKey",
    (
        SELECT MAX(TRY_CONVERT(date, TRY_CONVERT(char(8), haf."AdmissionDateKey"), 112))
        FROM "HospitalAdmissionFact" haf
        WHERE win."PatientDurableKey" = haf."PatientDurableKey"
            AND haf."Count" = 1
            AND haf."AdmissionDateKey" > 19000101
            AND haf."AdmissionDateKey" >= win."3MonthBeforeKey"
            AND haf."AdmissionDateKey" <= win."IndexDateKey"
            AND (haf."LengthOfStayInDays" IS NULL OR CAST(haf."LengthOfStayInDays" AS int) >= 3)
    ) AS "HospHxDate"
INTO #tmp_feat_hosp_hx
FROM #tmp_plan_window win
;

CREATE UNIQUE NONCLUSTERED INDEX UX_tmp_feat_hosp_hx_PDKey_TPKey ON #tmp_feat_hosp_hx ("PatientDurableKey", "TreatmentPlanKey");


DECLARE @sec7_end datetime2(3) = SYSDATETIME();
DECLARE @sec7_elapsed int = DATEDIFF(SECOND, @sec7_start, @sec7_end);
RAISERROR('Section 7 elapsed seconds: %d', 0, 1, @sec7_elapsed) WITH NOWAIT;


/*********************************************************************
** 8. Staging and regimen
*********************************************************************/
DECLARE @sec8_start datetime2(3) = SYSDATETIME();

-- =====================================================
-- TEMP TABLE: Epic staging (long)
-- =====================================================
DROP TABLE IF EXISTS #tmp_epic_stage_long;
SELECT
    "PatientDurableKey",
    CASE UPPER("StageGroupGeneral")
        WHEN 'IV' THEN 4
        WHEN 'III' THEN 3
        WHEN 'II' THEN 2
        WHEN 'I' THEN 1
        ELSE NULL
    END AS stage_num,
    COALESCE(
        CAST("StageEditInstant" AS date),
        TRY_CONVERT(date, TRY_CONVERT(char(8), "StageDateKey"), 112)
    ) AS stage_date,
    "StageEditInstant",
    "StageDateKey"
INTO #tmp_epic_stage_long
FROM "CancerStagingFact"
WHERE "Count" = 1
    AND "StageGroup" IS NOT NULL
    AND UPPER("StageGroup") NOT IN ('STAGE UNKNOWN','NO STAGE RECOMMENDED', '*UNSPECIFIED')
;

CREATE NONCLUSTERED INDEX IX_tmp_epic_stage_long_PDKey ON #tmp_epic_stage_long ("PatientDurableKey");
CREATE NONCLUSTERED INDEX IX_tmp_epic_stage_long_SNum ON #tmp_epic_stage_long (stage_num);


-- =====================================================
-- TEMP TABLE: Epic staging (wide)
-- =====================================================
DROP TABLE IF EXISTS #tmp_feat_epic_stage;
WITH global_ranked AS (
    SELECT
        "PatientDurableKey",
        stage_num,
        stage_date,
        ROW_NUMBER() OVER (
            PARTITION BY "PatientDurableKey"
            ORDER BY stage_num DESC, stage_date ASC
        ) AS row_num
    FROM #tmp_epic_stage_long
    WHERE stage_num IS NOT NULL
        AND stage_num >= 4
),
global_max AS (
    SELECT
        "PatientDurableKey",
        stage_num,
        stage_date
    FROM global_ranked
    WHERE row_num = 1
),
local_ranked AS (
    SELECT
        win."PatientDurableKey",
        win."TreatmentPlanKey",
        esl.stage_num,
        esl.stage_date,
        ROW_NUMBER() OVER (
            PARTITION BY win."PatientDurableKey", win."TreatmentPlanKey"
            ORDER BY esl.stage_num DESC, esl.stage_date ASC
        ) AS row_num
    FROM #tmp_plan_window win
    INNER JOIN #tmp_epic_stage_long esl
        ON win."PatientDurableKey" = esl."PatientDurableKey"
            AND (
                (
                    esl."StageEditInstant" IS NOT NULL
                    AND CAST(esl."StageEditInstant" AS datetime2) >= win."6MonthBefore"
                    AND CAST(esl."StageEditInstant" AS datetime2) <= win."6MonthAfter"
                )
                OR (
                    esl."StageEditInstant" IS NULL
                    AND esl."StageDateKey" >= win."6MonthBeforeKey"
                    AND esl."StageDateKey" <= win."6MonthAfterKey"
                )
            )
    WHERE esl.stage_num IS NOT NULL
),
local_max AS (
    SELECT
        "PatientDurableKey",
        "TreatmentPlanKey",
        stage_num,
        stage_date
    FROM local_ranked
    WHERE row_num = 1
)
SELECT
    win."PatientDurableKey",
    win."TreatmentPlanKey",
    CASE
        WHEN gstage.stage_num IS NOT NULL THEN gstage.stage_num
        ELSE lstage.stage_num
    END AS "EpicStage",
    CASE
        WHEN gstage.stage_num IS NOT NULL THEN gstage.stage_date
        ELSE lstage.stage_date
    END AS "EpicStageDate"
INTO #tmp_feat_epic_stage
FROM #tmp_plan_window win
LEFT JOIN local_max lstage
    ON win."PatientDurableKey" = lstage."PatientDurableKey"
        AND win."TreatmentPlanKey" = lstage."TreatmentPlanKey"
LEFT JOIN global_max gstage
    ON win."PatientDurableKey" = gstage."PatientDurableKey"
;

CREATE UNIQUE NONCLUSTERED INDEX UX_tmp_feat_epic_stage_PDKey_TPKey ON #tmp_feat_epic_stage ("PatientDurableKey", "TreatmentPlanKey");


-- =====================================================
-- TEMP TABLE: regimen (long)
-- =====================================================
DROP TABLE IF EXISTS #tmp_regimen_long;
WITH plan_orders AS (
    SELECT
        cohort."PatientDurableKey",
        cohort."TreatmentPlanKey",
        medorder."MedicationOrderKey",
        medorder."StartDateKey",
        meddim."Name",
        CASE
            WHEN UPPER(meddim."Name") LIKE 'ADO-TRASTUZUMAB%' THEN 'TRASTUZUMAB'
            WHEN UPPER(meddim."Name") LIKE 'FAM-TRASTUZUMAB%' THEN 'TRASTUZUMAB'
            WHEN UPPER(meddim."Name") LIKE '%IBRITUMOMAB%' THEN 'IBRITUMOMAB'
            WHEN UPPER(meddim."Name") LIKE 'TOSITUMOMAB%' THEN 'TOSITUMOMAB'
            WHEN UPPER(meddim."Name") LIKE 'ZIV-AFLIBERCEPT%' THEN 'AFLIBERCEPT'
            ELSE NULLIF(
                LEFT(
                    meddim."Name",
                    COALESCE(
                        NULLIF(
                            CHARINDEX(
                                ' ',
                                REPLACE(REPLACE(REPLACE(meddim."Name", '/', ' '), ',', ' '), '-', ' ')
                            ),
                            0
                        ) - 1,
                        LEN(meddim."Name")
                    )
                ),
                ''
               )
        END AS "NameNew"
    FROM #tmp_plan_cohort cohort
    INNER JOIN "TreatmentPlanMedicationOrderFact" medorder
        ON cohort."PatientDurableKey" = medorder."PatientDurableKey"
            AND cohort."TreatmentPlanKey" = medorder."TreatmentPlanKey"
            AND medorder."Count" = 1
    INNER JOIN "TreatmentPlanCycleDayFact" cycle 
        ON medorder."TreatmentPlanCycleDayKey" = cycle."TreatmentPlanCycleDayKey"
            AND cycle."Count" = 1
            AND cycle."CycleNumber" = 1
    INNER JOIN "MedicationDim" meddim
        ON medorder."MedicationKey" = meddim."MedicationKey"
    WHERE UPPER(medorder."Type") = 'MEDICATIONS'
)
SELECT
    po.*,
    lookup."ChemoType"
INTO #tmp_regimen_long
FROM plan_orders po
INNER JOIN #tmp_chemo_lookup lookup
    ON UPPER(po."NameNew") = lookup.med_name_upper
;

CREATE NONCLUSTERED INDEX IX_tmp_regimen_long_names ON #tmp_regimen_long ("PatientDurableKey", "TreatmentPlanKey", "ChemoType") INCLUDE ("NameNew");


-- =====================================================
-- TEMP TABLE: regimen (wide)
-- =====================================================
DROP TABLE IF EXISTS #tmp_feat_regimen;
WITH base_plans AS (
    SELECT DISTINCT
        "PatientDurableKey",
        "TreatmentPlanKey"
    FROM #tmp_regimen_long
),
order_flags_dates AS (
    SELECT
        "PatientDurableKey",
        "TreatmentPlanKey",
        MAX(CASE WHEN "ChemoType" = 'chemo' THEN 1 ELSE 0 END) AS "HasChemoOrder",
        MAX(CASE WHEN "ChemoType" = 'endo' THEN 1 ELSE 0 END) AS "HasEndoOrder",
        MAX(CASE WHEN "ChemoType" = 'target' THEN 1 ELSE 0 END) AS "HasTargetOrder",
        MAX(CASE WHEN "ChemoType" IN ('immune-ici','immune-cart','immune-other') THEN 1 ELSE 0 END) AS "HasImmuneOrder",
        MAX(
            CASE WHEN "ChemoType" = 'chemo'
                THEN TRY_CONVERT(date, TRY_CONVERT(char(8), "StartDateKey"), 112)
            END
        ) AS "ChemoDateOrder",
        MAX(
            CASE WHEN "ChemoType" = 'endo'
                THEN TRY_CONVERT(date, TRY_CONVERT(char(8), "StartDateKey"), 112)
            END
        ) AS "EndoDateOrder",
        MAX(
            CASE WHEN "ChemoType" = 'target'
                THEN TRY_CONVERT(date, TRY_CONVERT(char(8), "StartDateKey"), 112)
            END
        ) AS "TargetDateOrder",
        MAX(
            CASE WHEN "ChemoType" IN ('immune-ici','immune-cart','immune-other')
                THEN TRY_CONVERT(date, TRY_CONVERT(char(8), "StartDateKey"), 112)
            END
        ) AS "ImmuneDateOrder"
    FROM #tmp_regimen_long
    WHERE "StartDateKey" IS NOT NULL
    GROUP BY "PatientDurableKey", "TreatmentPlanKey"
),
order_distinct_names AS (
    SELECT DISTINCT
        "PatientDurableKey",
        "TreatmentPlanKey",
        "ChemoType",
        "Name"
    FROM #tmp_regimen_long
    WHERE "StartDateKey" IS NOT NULL
),
order_grouped_names AS (
    SELECT
        "PatientDurableKey",
        "TreatmentPlanKey",
        "ChemoType",
        STRING_AGG(
            CAST("Name" AS nvarchar(max)),
            N','
        ) WITHIN GROUP (
            ORDER BY "Name"
        ) AS "Names"
    FROM order_distinct_names
    GROUP BY "PatientDurableKey", "TreatmentPlanKey", "ChemoType"
),
order_agg AS (
    SELECT
        order_flags_dates."PatientDurableKey",
        order_flags_dates."TreatmentPlanKey",
        order_flags_dates."HasChemoOrder",
        order_flags_dates."HasEndoOrder",
        order_flags_dates."HasTargetOrder",
        order_flags_dates."HasImmuneOrder",
        order_flags_dates."ChemoDateOrder",
        order_flags_dates."EndoDateOrder",
        order_flags_dates."TargetDateOrder",
        order_flags_dates."ImmuneDateOrder",
        MAX(
            CASE WHEN order_grouped_names."ChemoType" = 'chemo' THEN order_grouped_names."Names" END
        ) AS "ChemoNamesOrder",
        MAX(
            CASE WHEN order_grouped_names."ChemoType" = 'endo' THEN order_grouped_names."Names" END
        ) AS "EndoNamesOrder",
        MAX(
            CASE WHEN order_grouped_names."ChemoType" = 'target' THEN order_grouped_names."Names" END
        ) AS "TargetNamesOrder",
        MAX(
            CASE WHEN order_grouped_names."ChemoType" IN ('immune-ici','immune-cart','immune-other') THEN order_grouped_names."Names" END
        ) AS "ImmuneNamesOrder"
    FROM order_flags_dates
    LEFT JOIN order_grouped_names
        ON order_flags_dates."PatientDurableKey" = order_grouped_names."PatientDurableKey"
            AND order_flags_dates."TreatmentPlanKey" = order_grouped_names."TreatmentPlanKey"
    GROUP BY
        order_flags_dates."PatientDurableKey", order_flags_dates."TreatmentPlanKey",
        order_flags_dates."HasChemoOrder", order_flags_dates."HasEndoOrder", order_flags_dates."HasTargetOrder", order_flags_dates."HasImmuneOrder",
        order_flags_dates."ChemoDateOrder", order_flags_dates."EndoDateOrder", order_flags_dates."TargetDateOrder", order_flags_dates."ImmuneDateOrder"
)
SELECT
    base_plans."PatientDurableKey",
    base_plans."TreatmentPlanKey",
    COALESCE(order_agg."HasChemoOrder", 0) AS "HasChemo",
    COALESCE(order_agg."HasEndoOrder", 0) AS "HasEndo",
    COALESCE(order_agg."HasTargetOrder", 0) AS "HasTarget",
    COALESCE(order_agg."HasImmuneOrder", 0) AS "HasImmune",
    order_agg."ChemoNamesOrder" AS "ChemoNames",
    order_agg."EndoNamesOrder" AS "EndoNames",
    order_agg."TargetNamesOrder" AS "TargetNames",
    order_agg."ImmuneNamesOrder" AS "ImmuneNames",
    order_agg."ChemoDateOrder" AS "ChemoDate",
    order_agg."EndoDateOrder" AS "EndoDate",
    order_agg."TargetDateOrder" AS "TargetDate",
    order_agg."ImmuneDateOrder" AS "ImmuneDate"
INTO #tmp_feat_regimen
FROM base_plans
LEFT JOIN order_agg
    ON base_plans."PatientDurableKey" = order_agg."PatientDurableKey"
        AND base_plans."TreatmentPlanKey" = order_agg."TreatmentPlanKey"
;

CREATE UNIQUE NONCLUSTERED INDEX UX_tmp_feat_regimen_PDKey_TPKey ON #tmp_feat_regimen ("PatientDurableKey", "TreatmentPlanKey");


DECLARE @sec8_end datetime2(3) = SYSDATETIME();
DECLARE @sec8_elapsed int = DATEDIFF(SECOND, @sec8_start, @sec8_end);
RAISERROR('Section 8 elapsed seconds: %d', 0, 1, @sec8_elapsed) WITH NOWAIT;


/*********************************************************************
** 9. Final query
*********************************************************************/
WITH features AS (
    SELECT
        cohort."DataPullDate",
        cohort."IndexDate",
        -- demographics
        demog."PatientName",
        demog."PatientMRN",
        prov."ProviderName",
        prov."ProviderEmail",
        prov."ProviderLocation",
        demog."Age",
        demog."Sex",
        demog."CleanRace",
        demog."CleanEthnicity",
        -- visits
        visit."LastInfusionDate",
        visit."PlannedInfusionDate",
        visit."LastOncDate",
        visit."PlannedOncDate",
        -- patient/plan info
        cohort."PatientDurableKey",
        cohort."TreatmentPlanKey",
        cohort."PatientEpicId",
        cohort."PlanEpicId",
        cohort."PlanNum",
        cohort."PlanDisplayName",
        cohort."PlanStatus",
        cohort."PlanCreatedOnDate",
        cohort."PlanDiscontinueReason",
        cohort."Plan_CreationInstant",
        cohort."Plan_LastUpdatedInstant",
        cohort."PrevScheduledPlanDate",
        cohort."ScheduledPlanDate",
        cohort."ScheduledTreatmentDate",
        cohort."TreatmentAdminStartDate",
        cohort."TreatmentOrderStartDate",
        -- cancer
        cancer."CancerType",
        CASE
            WHEN cancer."CancerType" IS NULL THEN 99
            WHEN cancer."CancerType" IN (
                'lung', 'gu_kidney', 'gu_bladder', 'gu_testicular', 'gyn_uterine', 'gyn_ovarian', 'gyn_cervical',
                'gyn_vaginal', 'gyn_vulvar', 'lymphoma_lymphoblastic', 'lymphoma_systemic t and nk', 'lymphoma_dlbcl',
                'lymphoma_burkitt', 'lymphoma_cutaneous t cell', 'lymphoma_follicular', 'lymphoma_hodgkin',
                'lymphoma_mantle', 'lymphoma_other'
            ) THEN 1
            WHEN cancer."CancerType" IN ('gi_gastric', 'gi_pancreas') THEN 2
            ELSE 0
        END AS "CancerKhoranaScore",
        CASE
            WHEN cancer."CancerType" IS NULL THEN 99
            WHEN cancer."CancerType" IN ('gi_colorectal', 'gi_intestinal') THEN 1
            WHEN cancer."CancerType" IN (
                'lung', 'gu_kidney', 'gu_bladder', 'gu_testicular', 'gyn_uterine', 'gyn_ovarian',
                'myeloma', 'cns', 'sarcoma_soft tissue', 'leukemia_all',
                'lymphoma_lymphoblastic', 'lymphoma_systemic t and nk', 'lymphoma_dlbcl', 'lymphoma_burkitt'
            ) THEN 2
            WHEN cancer."CancerType" IN ('gi_cholangio and gallbladder', 'gi_esophageal', 'gi_gastric', 'gi_pancreas') THEN 3
            ELSE 0
        END AS "CancerEhrCatScore",
        CASE
            WHEN "CancerType" IS NULL THEN 99
            WHEN "CancerType" IN ('leukemia_all', 'leukemia_aml', 'mpn_cml', 'mpn_cmml', 'mpn_mast', 'mpn_pv', 'mpn_et', 'mpn_pmf', 'mds', 'cns') THEN 1
            ELSE 0
        END AS "ExcCancer",
        -- stage
        epicstage."EpicStage",
        epicstage."EpicStageDate",
        met."HasMetastaticICD",
        met."MetastaticICDDate",
        CASE
            WHEN epicstage."EpicStage" IS NULL AND met."HasMetastaticICD" = 0 THEN 99
            WHEN COALESCE(epicstage."EpicStage", 0) >= 4
                OR met."HasMetastaticICD" = 1
            THEN 1
            ELSE 0
        END AS "StageScore",
        -- regimen
        regimen."HasChemo",
        regimen."HasEndo",
        regimen."HasTarget",
        regimen."HasImmune",
        regimen."ChemoDate",
        regimen."EndoDate",
        regimen."TargetDate",
        regimen."ImmuneDate",
        regimen."ChemoNames",
        regimen."EndoNames",
        regimen."TargetNames",
        regimen."ImmuneNames",
        CASE
            WHEN COALESCE(regimen."HasChemo", 0) = 0
                AND COALESCE(regimen."HasImmune", 0) = 0
                AND COALESCE(regimen."HasTarget", 0) = 0
                AND COALESCE(regimen."HasEndo", 0) = 1
            THEN -1 ELSE 0
        END AS "EndoScore",
        -- vitals
        vital."WeightKg",
        vital."WeightInstant",
        vital."HeightCm",
        vital."HeightInstant",
        vital."BMI",
        CASE
            WHEN vital."BMI" IS NULL THEN 99
            WHEN vital."BMI" >= 35 THEN 1
            ELSE 0
        END AS "BMIScore",
        -- labs
        lab."WBCValue",
        lab."WBCInstant",
        CASE
            WHEN lab."WBCValue" IS NULL THEN 99
            WHEN lab."WBCValue" > 11 THEN 1
            ELSE 0
        END AS "WBCScore",
        lab."HgbValue",
        lab."HgbInstant",
        CASE
            WHEN lab."HgbValue" IS NULL THEN 99
            WHEN lab."HgbValue" < 10 THEN 1
            ELSE 0
        END AS "HgbScore",  
        lab."PltValue",
        lab."PltInstant",
        CASE
            WHEN lab."PltValue" IS NULL THEN 99
            WHEN lab."PltValue" >= 350 THEN 1
            ELSE 0
        END AS "PltScore",
        lab."ALTValue",
        lab."ALTInstant",
        lab."ASTValue",
        lab."ASTInstant",
        lab."CrValue",
        lab."CrInstant",
        CASE
            WHEN lab."ALTValue" IS NOT NULL AND lab."ALTValue" > 234 THEN 1
            WHEN lab."ASTValue" IS NOT NULL AND lab."ASTValue" > 111 THEN 1
            WHEN lab."ALTValue" IS NULL OR lab."ASTValue" IS NULL THEN 99
            ELSE 0
        END AS "ExcAltAst",
        CASE
            WHEN "Age" IS NULL OR "WeightKg" IS NULL OR "CrValue" IS NULL OR "Sex" IS NULL THEN 99
            WHEN (
                ((140 - "Age") * "WeightKg") / (72.0 * "CrValue")
                * CASE WHEN "Sex" = 'Female' THEN 0.85 ELSE 1.0 END
            ) < 30.0
            THEN 1
            ELSE 0
        END AS "ExcEGFR",
        -- vte history
        vte."VteHxDate",
        CASE
            WHEN vte."VteHxDate" IS NULL THEN 0
            ELSE 1
        END AS "VteHxScore",
        -- paralysis history
        para."ParalysisHxDate",
        CASE
            WHEN para."ParalysisHxDate" IS NULL THEN 0
            ELSE 1
        END AS "ParalysisHxScore",
        -- hospitalization history
        hosp."HospHxDate",
        CASE
            WHEN hosp."HospHxDate" IS NULL THEN 0
            ELSE 1
        END AS "HospHxScore",
        -- asian
        CASE
            WHEN demog."CleanRace" IS NULL THEN 99
            WHEN demog."CleanRace" IN ('Asian','Native Hawaiian or Other Pacific Islander') THEN -1
            ELSE 0
        END AS "RaceScore",
        -- AC
        COALESCE(ipmeds."IpAcCnt", 0) AS "IpAc",
        ipmeds."IpAcDate",
        ipmeds."IpAcSGN",
        COALESCE(opmeds."OpAcCnt", 0) AS "OpAc",
        opmeds."OpAcDate",
        opmeds."OpAcSGN",
        COALESCE(repmeds."ReportedAcCnt", 0) AS "ReportedAc",
        repmeds."ReportedAcDate",
        repmeds."ReportedAcSGN",
        CASE
            WHEN COALESCE(ipmeds."IpAcCnt", 0) > 0 OR COALESCE(opmeds."OpAcCnt", 0) > 0 OR COALESCE(repmeds."ReportedAcCnt", 0) > 0
            THEN 1 ELSE 0
        END AS "ExcAC",
        -- Contraind
        COALESCE(ipmeds."IpContraindCnt", 0) AS "IpContraind",
        ipmeds."IpContraindDate",
        ipmeds."IpContraindSGN",
        COALESCE(opmeds."OpContraindCnt", 0) AS "OpContraind",
        opmeds."OpContraindDate",
        opmeds."OpContraindSGN",
        COALESCE(repmeds."ReportedContraindCnt", 0) AS "ReportedContraind",
        repmeds."ReportedContraindDate",
        repmeds."ReportedContraindSGN",
        -- Statin
        COALESCE(ipmeds."IpStatinCnt", 0) AS "IpStatin",
        ipmeds."IpStatinDate",
        ipmeds."IpStatinSGN",
        COALESCE(opmeds."OpStatinCnt", 0) AS "OpStatin",
        opmeds."OpStatinDate",
        opmeds."OpStatinSGN",
        COALESCE(repmeds."ReportedStatinCnt", 0) AS "ReportedStatin",
        repmeds."ReportedStatinDate",
        repmeds."ReportedStatinSGN",
        CASE
            WHEN COALESCE(ipmeds."IpStatinCnt", 0) > 0 OR COALESCE(opmeds."OpStatinCnt", 0) > 0 OR COALESCE(repmeds."ReportedStatinCnt", 0) > 0
            THEN 1 ELSE 0
        END AS "ExcStatin"
    FROM #tmp_plan_cohort cohort
    LEFT JOIN #tmp_feat_provider prov
        ON cohort."PatientDurableKey" = prov."PatientDurableKey"
            AND cohort."TreatmentPlanKey" = prov."TreatmentPlanKey"
    LEFT JOIN #tmp_feat_cancer cancer
        ON cohort."PatientDurableKey" = cancer."PatientDurableKey"
            AND cohort."TreatmentPlanKey" = cancer."TreatmentPlanKey"
    LEFT JOIN #tmp_feat_regimen regimen
        ON cohort."PatientDurableKey" = regimen."PatientDurableKey"
            AND cohort."TreatmentPlanKey" = regimen."TreatmentPlanKey"
    LEFT JOIN #tmp_feat_epic_stage epicstage
        ON cohort."PatientDurableKey" = epicstage."PatientDurableKey"
            AND cohort."TreatmentPlanKey" = epicstage."TreatmentPlanKey"
    LEFT JOIN #tmp_feat_met_icd met
        ON cohort."PatientDurableKey" = met."PatientDurableKey"
            AND cohort."TreatmentPlanKey" = met."TreatmentPlanKey"
    LEFT JOIN #tmp_feat_vitals vital
        ON cohort."PatientDurableKey" = vital."PatientDurableKey"
            AND cohort."TreatmentPlanKey" = vital."TreatmentPlanKey"
    LEFT JOIN #tmp_feat_labs lab
        ON cohort."PatientDurableKey" = lab."PatientDurableKey"
            AND cohort."TreatmentPlanKey" = lab."TreatmentPlanKey"
    LEFT JOIN #tmp_feat_demog demog
        ON cohort."PatientDurableKey" = demog."PatientDurableKey"
            AND cohort."TreatmentPlanKey" = demog."TreatmentPlanKey"
    LEFT JOIN #tmp_feat_vte_hx vte
        ON cohort."PatientDurableKey" = vte."PatientDurableKey"
            AND cohort."TreatmentPlanKey" = vte."TreatmentPlanKey"
    LEFT JOIN #tmp_feat_paralysis_hx para
        ON cohort."PatientDurableKey" = para."PatientDurableKey"
            AND cohort."TreatmentPlanKey" = para."TreatmentPlanKey"
    LEFT JOIN #tmp_feat_hosp_hx hosp
        ON cohort."PatientDurableKey" = hosp."PatientDurableKey"
            AND cohort."TreatmentPlanKey" = hosp."TreatmentPlanKey"
    LEFT JOIN #tmp_feat_ip_meds ipmeds
        ON cohort."PatientDurableKey" = ipmeds."PatientDurableKey"
            AND cohort."TreatmentPlanKey" = ipmeds."TreatmentPlanKey"
    LEFT JOIN #tmp_feat_op_meds opmeds
        ON cohort."PatientDurableKey" = opmeds."PatientDurableKey"
            AND cohort."TreatmentPlanKey" = opmeds."TreatmentPlanKey"
    LEFT JOIN #tmp_feat_reported_meds repmeds
        ON cohort."PatientDurableKey" = repmeds."PatientDurableKey"
            AND cohort."TreatmentPlanKey" = repmeds."TreatmentPlanKey"
    LEFT JOIN #tmp_feat_visits visit
        ON cohort."PatientDurableKey" = visit."PatientDurableKey"
            AND cohort."TreatmentPlanKey" = visit."TreatmentPlanKey"
    WHERE cancer."CancerType" IS NOT NULL
)
SELECT
    "DataPullDate",
    "IndexDate",
    "PatientName",
    "PatientMRN",
    "ProviderName",
    "ProviderEmail",
    "ProviderLocation",
    "Age",
    "Sex",
    "CleanRace",
    "CleanEthnicity",
    "LastInfusionDate",
    "PlannedInfusionDate",
    "LastOncDate",
    "PlannedOncDate",
    "PatientDurableKey",
    "TreatmentPlanKey",
    "PatientEpicId",
    "PlanEpicId",
    "PlanNum",
    "PlanDisplayName",
    "PlanStatus",
    "PlanCreatedOnDate",
    "PlanDiscontinueReason",
    "Plan_CreationInstant",
    "Plan_LastUpdatedInstant",
    "PrevScheduledPlanDate",
    "ScheduledPlanDate",
    "ScheduledTreatmentDate",
    "TreatmentAdminStartDate",
    "TreatmentOrderStartDate",
    "CancerType",
    "CancerKhoranaScore",
    "CancerEhrCatScore",
    "EpicStage",
    "EpicStageDate",
    "HasMetastaticICD",
    "MetastaticICDDate",
    "StageScore",
    "HasChemo",
    "HasEndo",
    "HasTarget",
    "HasImmune",
    "ChemoDate",
    "EndoDate",
    "TargetDate",
    "ImmuneDate",
    "ChemoNames",
    "EndoNames",
    "TargetNames",
    "ImmuneNames",
    "EndoScore",
    "WeightKg",
    "WeightInstant",
    "HeightCm",
    "HeightInstant",
    "BMI",
    "BMIScore",
    "WBCValue",
    "WBCInstant",
    "WBCScore",
    "HgbValue",
    "HgbInstant",
    "HgbScore",  
    "PltValue",
    "PltInstant",
    "PltScore",
    "VteHxDate",
    "VteHxScore",
    "ParalysisHxDate",
    "ParalysisHxScore",
    "HospHxDate",
    "HospHxScore",
    "RaceScore",
    (
        CASE WHEN "CancerKhoranaScore" = 99 THEN 1 ELSE 0 END
        + CASE WHEN "BMIScore" = 99 THEN 1 ELSE 0 END
        + CASE WHEN "WBCScore" = 99 THEN 1 ELSE 0 END
        + CASE WHEN "HgbScore" = 99 THEN 1 ELSE 0 END
        + CASE WHEN "PltScore" = 99 THEN 1 ELSE 0 END
    ) AS "KhoranaMissingCount",
    (
        CASE WHEN "CancerEhrCatScore" = 99 THEN 1 ELSE 0 END
        + CASE WHEN "BMIScore" = 99 THEN 1 ELSE 0 END
        + CASE WHEN "WBCScore" = 99 THEN 1 ELSE 0 END
        + CASE WHEN "HgbScore" = 99 THEN 1 ELSE 0 END
        + CASE WHEN "PltScore" = 99 THEN 1 ELSE 0 END
        + CASE WHEN "StageScore" = 99 THEN 1 ELSE 0 END
        + CASE WHEN "EndoScore" = 99 THEN 1 ELSE 0 END
        + CASE WHEN "RaceScore" = 99 THEN 1 ELSE 0 END
    ) AS "EhrCatMissingCount",
    (
        CASE WHEN "CancerKhoranaScore" = 99 THEN 0 ELSE "CancerKhoranaScore" END
        + CASE WHEN "BMIScore" = 99 THEN 0 ELSE "BMIScore" END
        + CASE WHEN "WBCScore" = 99 THEN 0 ELSE "WBCScore" END
        + CASE WHEN "HgbScore" = 99 THEN 0 ELSE "HgbScore" END
        + CASE WHEN "PltScore" = 99 THEN 0 ELSE "PltScore" END
    ) AS "KhoranaScore",
    (
        CASE WHEN "CancerEhrCatScore" = 99 THEN 0 ELSE "CancerEhrCatScore" END
        + CASE WHEN "BMIScore" = 99 THEN 0 ELSE "BMIScore" END
        + CASE WHEN "WBCScore" = 99 THEN 0 ELSE "WBCScore" END
        + CASE WHEN "HgbScore" = 99 THEN 0 ELSE "HgbScore" END
        + CASE WHEN "PltScore" = 99 THEN 0 ELSE "PltScore" END
        + CASE WHEN "StageScore" = 99 THEN 0 ELSE "StageScore" END
        + "VteHxScore"
        + "ParalysisHxScore"
        + "HospHxScore"
        + CASE WHEN "EndoScore" = 99 THEN 0 ELSE "EndoScore" END
        + CASE WHEN "RaceScore" = 99 THEN 0 ELSE "RaceScore" END
    ) AS "EhrCatScore",
    "IpAc",
    "IpAcDate",
    "IpAcSGN",
    "OpAc",
    "OpAcDate",
    "OpAcSGN",
    "ReportedAc",
    "ReportedAcDate",
    "ReportedAcSGN",
    "IpContraind",
    "IpContraindDate",
    "IpContraindSGN",
    "OpContraind",
    "OpContraindDate",
    "OpContraindSGN",
    "ReportedContraind",
    "ReportedContraindDate",
    "ReportedContraindSGN",
    "IpStatin",
    "IpStatinDate",
    "IpStatinSGN",
    "OpStatin",
    "OpStatinDate",
    "OpStatinSGN",
    "ReportedStatin",
    "ReportedStatinDate",
    "ReportedStatinSGN",
    "ALTValue",
    "ALTInstant",
    "ASTValue",
    "ASTInstant",
    "CrValue",
    "CrInstant",
    "ExcStatin",
    "ExcAC",
    "ExcCancer",
    "ExcEGFR",
    "ExcAltAst",
    CONCAT(
        'https://statin.angli-lab.com/en?',
        'rcancerkho=', CAST("CancerKhoranaScore" AS varchar(2)),
        '&rcancerehr=', CAST("CancerEhrCatScore" AS varchar(2)),
        '&rbmi=', CAST("BMIScore" AS varchar(2)),
        '&rwbc=', CAST("WBCScore" AS varchar(2)),
        '&rhgb=', CAST("HgbScore" AS varchar(2)),
        '&rplt=', CAST("PltScore" AS varchar(2)),
        '&rstage=', CAST("StageScore" AS varchar(2)),
        '&rvte=', CAST("VteHxScore" AS varchar(2)),
        '&rparal=', CAST("ParalysisHxScore" AS varchar(2)),
        '&rhosp=', CAST("HospHxScore" AS varchar(2)),
        '&rendo=', CAST("EndoScore" AS varchar(2)),
        '&rasian=', CAST("RaceScore" AS varchar(2)),
        '&xstatin=', CAST("ExcStatin" AS varchar(2)),
        '&xac=', CAST("ExcAC" AS varchar(2)),
        '&xcancer=', CAST("ExcCancer" AS varchar(2)),
        '&xegfr=', CAST("ExcEGFR" AS varchar(2)),
        '&xaltast=', CAST("ExcAltAst" AS varchar(2))
    ) AS "Link"
FROM features
ORDER BY "PatientDurableKey", "PlanNum"
;
