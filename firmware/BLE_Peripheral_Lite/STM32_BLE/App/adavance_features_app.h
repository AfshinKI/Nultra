/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    Adavance_features_app.h
  * @author  MCD Application Team
  * @brief   Header for Adavance_features_app.c
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
#ifndef ADAVANCE_FEATURES_APP_H
#define ADAVANCE_FEATURES_APP_H

#ifdef __cplusplus
extern "C" {
#endif

/* Includes ------------------------------------------------------------------*/
/* USER CODE BEGIN Includes */

/* USER CODE END Includes */

/* Exported types ------------------------------------------------------------*/
typedef enum
{
  ADAVANCE_FEATURES_CONN_HANDLE_EVT,
  ADAVANCE_FEATURES_DISCON_HANDLE_EVT,

  /* USER CODE BEGIN Service2_OpcodeNotificationEvt_t */

  /* USER CODE END Service2_OpcodeNotificationEvt_t */

  ADAVANCE_FEATURES_LAST_EVT,
} ADAVANCE_FEATURES_APP_OpcodeNotificationEvt_t;

typedef struct
{
  ADAVANCE_FEATURES_APP_OpcodeNotificationEvt_t          EvtOpcode;
  uint16_t                                 ConnectionHandle;

  /* USER CODE BEGIN ADAVANCE_FEATURES_APP_ConnHandleNotEvt_t */

  /* USER CODE END ADAVANCE_FEATURES_APP_ConnHandleNotEvt_t */
} ADAVANCE_FEATURES_APP_ConnHandleNotEvt_t;
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
void ADAVANCE_FEATURES_APP_Init(void);
void ADAVANCE_FEATURES_APP_EvtRx(ADAVANCE_FEATURES_APP_ConnHandleNotEvt_t *p_Notification);
void ADAVANCE_FEATURES_APP_Process(void);
/* USER CODE BEGIN EF */

/* USER CODE END EF */

#ifdef __cplusplus
}
#endif

#endif /*ADAVANCE_FEATURES_APP_H */
