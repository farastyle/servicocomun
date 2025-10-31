CREATE TABLE IF NOT EXISTS `community_service` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `citizenid` VARCHAR(50) NOT NULL,
  `playerServerId` INT DEFAULT NULL,
  `serviceType` VARCHAR(50) NOT NULL,
  `startedAt` INT DEFAULT 0,
  `durationMin` INT NOT NULL,
  `method` VARCHAR(20) DEFAULT 'teleport',
  `active` TINYINT(1) DEFAULT 1,
  `createdAt` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  INDEX `citizen_idx` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
