-- Audit finding: candidate search must not scale with driver density. Dispatch now takes the N nearest eligible drivers by KNN (GiST).
INSERT INTO application_settings(key,value,description) VALUES
('dispatch.candidate_pool','30','Nearest eligible drivers considered per dispatch round (KNN pool)');
