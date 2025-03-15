/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    Adavance_features.h
  * @author  MCD Application Team
  * @brief   Header for Adavance_features.c
  ******************************************************************************
  * @attention
  *
  * Copyright (c) 2025 STMicroelectronics.
  * All rights reserved.
  *
  * This software is licensed under terms that can be found in the LICENSE file
  * in the root directory of this software component.
  * If no LICENSE file comes with this software, it is provided AS-IS.
  *
  ******************************************************************************
  */
/* USER CODE END Header */

/* Define to prevent recursive inclusion -------------------------------------*/
#ifndef ADAVANCE_FEATURES_H
#define ADAVANCE_FEATURES_H

#ifdef __cplusplus
extern "C" {
#endif

/* Includes ------------------------------------------------------------------*/
#include "ble_status.h"
/* USER CODE BEGIN Includes */

/* USER CODE END Includes */

/* Exported defines ----------------------------------------------------------*/
/* USER CODE BEGIN ED */

/* USER CODE END ED */

/* Exported types ------------------------------------------------------------*/
typedef enum
{
  ADAVANCE_FEATURES_VERSION,

  /* USER CODE BEGIN Service2_CharOpcode_t */

  /* USER CODE END Service2_CharOpcode_t */

  ADAVANCE_FEATURES_CHAROPCODE_LAST
} ADAVANCE_FEATURES_CharOpcode_t;

typedef enum
{
  ADAVANCE_FEATURES_VERSION_READ_EVT,

  /* USER CODE BEGIN Service2_OpcodeEvt_t */

  /* USER CODE END Service2_OpcodeEvt_t */

  ADAVANCE_FEATURES_BOOT_REQUEST_EVT
} ADAVANCE_FEATURES_OpcodeEvt_t;

typedef struct
{
  uint8_t *p_Payload;
  uint8_t Length;

  /* USER CODE BEGIN Service2_Data_t */

  /* USER CODE END Service2_Data_t */

} ADAVANCE_FEATURES_Data_t;

typedef struct
{
  ADAVANCE_FEATURES_OpcodeEvt_t       EvtOpcode;
  ADAVANCE_FEATURES_Data_t             DataTransfered;
  uint16_t                ConnectionHandle;
  uint16_t                AttributeHandle;
  uint8_t                 ServiceInstance;

  /* USER CODE BEGIN Service2_NotificationEvt_t */

  /* USER CODE END Service2_NotificationEvt_t */

} ADAVANCE_FEATURES_NotificationEvt_t;

/* USER CODE BEGIN ET */

/* USER CODE END ET */

/* Exported constants --------------------------------------------------------*/
/* USER CODE BEGIN EC */

/* USER CODE END EC */

/* External variables --------------------------------------------------------*/
/* USER CODE BEGIN EV */

/* USER CODE END EV */

/* Exported macros -----------------------------------------------------------*/
/* USER CODE BEGIN EM */

/* USER CODE END EM */

/* Exported functions ------------------------------------------------------- */
void ADAVANCE_FEATURES_Init(void);
void ADAVANCE_FEATURES_Notification(ADAVANCE_FEATURES_NotificationEvt_t *p_Notification);
tBleStatus ADAVANCE_FEATURES_UpdateValue(ADAVANCE_FEATURES_CharOpcode_t CharOpcode, ADAVANCE_FEATURES_Data_t *pData);
tBleStatus ADAVANCE_FEATURES_NotifyValue(ADAVANCE_FEATURES_CharOpcode_t CharOpcode, ADAVANCE_FEATURES_Data_t *pData, uint16_t ConnectionHandle);
/* USER CODE BEGIN EF */

/* USER CODE END EF */

#ifdef __cplusplus
}
#endif

#endif /*ADAVANCE_FEATURES_H */
