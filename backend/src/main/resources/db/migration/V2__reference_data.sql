-- Reference/configuration data required for launch in Almaty. All values are editable via Admin.
INSERT INTO cities(code,name_kk,name_ru,name_en) VALUES ('ALA','Алматы','Алматы','Almaty');

INSERT INTO service_zones(city_id,name,boundary)
SELECT id,'Almaty core',
 ST_GeogFromText('POLYGON((76.75 43.12, 77.15 43.12, 77.15 43.42, 76.75 43.42, 76.75 43.12))') FROM cities WHERE code='ALA';

INSERT INTO vehicle_categories(code,rank,name_kk,name_ru,name_en,desc_kk,desc_ru,desc_en,capacity) VALUES
('ECONOMY',1,'JOLAY Эконом','JOLAY Эконом','JOLAY Economy','Күнделікті қолжетімді жол','Доступные ежедневные поездки','Affordable daily transportation',4),
('COMFORT',2,'JOLAY Комфорт','JOLAY Комфорт','JOLAY Comfort','Кеңірек әрі ыңғайлы','Просторнее и комфортнее','More spacious and comfortable',4),
('BUSINESS',3,'JOLAY Бизнес','JOLAY Бизнес','JOLAY Business','Премиум көлік','Премиальные поездки','Premium transportation',4),
('XL',4,'JOLAY XL','JOLAY XL','JOLAY XL','Үлкен көліктер мен топтарға','Большие авто для компаний','Larger vehicles and groups',6);

INSERT INTO pricing_rules(city_id,category_code,base_fare,per_km,per_minute,min_fare,booking_fee,cancellation_fee,commission_rate)
SELECT c.id, v.code, v.base, v.km, v.min, v.minfare, v.booking, v.cancel, v.comm FROM cities c, (VALUES
 ('ECONOMY',300,110,18,600,0,300,0.1500),
 ('COMFORT',400,150,25,800,0,400,0.1500),
 ('BUSINESS',700,230,40,1500,0,700,0.1800),
 ('XL',600,190,32,1200,0,600,0.1500)) AS v(code,base,km,min,minfare,booking,cancel,comm)
WHERE c.code='ALA';

INSERT INTO application_settings(key,value,description) VALUES
('dispatch.offer_timeout_seconds','15','Time a driver has to accept an offer'),
('dispatch.initial_radius_m','2000','First search radius'),
('dispatch.max_radius_m','6000','Maximum search radius'),
('dispatch.radius_step_m','1000','Radius expansion step per round'),
('dispatch.search_timeout_seconds','120','Total time to find a driver before the ride expires'),
('dispatch.location_max_age_seconds','60','Driver locations older than this are ignored'),
('dispatch.max_candidates_per_round','5','Offers tried in one pass'),
('rides.detour_factor','1.30','Straight-line to road distance factor used by the development route provider'),
('rides.avg_speed_kmh','28','Average speed used by the development route provider'),
('rides.arrive_radius_m','400','Max distance between driver and pickup to mark arrival'),
('rides.max_fare_over_estimate','1.50','Final fare is capped at estimate x this factor'),
('wallet.driver_min_balance','-20000.00','Driver wallet floor when owing commission on cash rides');

INSERT INTO accounts(type) VALUES ('PLATFORM_REVENUE'),('EXTERNAL_CARD'),('EXTERNAL_CASH'),('PROMO');

INSERT INTO places(city_id,name,address,location)
SELECT c.id, p.n, p.a, ST_SetSRID(ST_MakePoint(p.lon,p.lat),4326)::geography FROM cities c, (VALUES
 ('Mega Alma-Ata','Rozybakieva St 247A',76.9066,43.2025),
 ('Dostyk Plaza','Samal-2, Dostyk Ave 111',76.9567,43.2335),
 ('Almaty-1 Railway Station','Zhetysu-2 / Raiymbek Ave',76.9486,43.3412),
 ('Almaty-2 Railway Station','Seifullin Ave 2',76.9438,43.2666),
 ('Almaty International Airport','Zhetysu 2, Turksib',77.0405,43.3521),
 ('Panfilov Park','Kabanbay Batyr St',76.9488,43.2594),
 ('Medeu','Gornaya St, Medeu',77.0589,43.1573),
 ('Kok-Tobe','Kok-Tobe Hill',76.9758,43.2297),
 ('Al-Farabi Kazakh National University','Al-Farabi Ave 71',76.9283,43.2237),
 ('Esentai Mall','Al-Farabi Ave 77/8',76.9283,43.2186),
 ('Republic Square','Republic Square',76.9453,43.2380),
 ('Sairan Bus Station','Tole Bi / Rayymbek',76.8672,43.2501)) AS p(n,a,lon,lat)
WHERE c.code='ALA';
