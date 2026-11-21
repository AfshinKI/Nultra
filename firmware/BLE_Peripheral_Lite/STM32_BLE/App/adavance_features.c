/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    Adavance_features.c
  * @author  MCD Application Team
  * @brief   Adavance_features definition.
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

/* Includes ------------------------------------------------------------------*/
#include <app_common.h>
#include "ble.h"
#include "adavance_features.h"
#include "adavance_features_app.h"
#include "ble_evt.h"

/* USER CODE BEGIN Includes */

/* USER CODE END Includes */

/* Private typedef -----------------------------------------------------------*/

/* USER CODE BEGIN PTD */

/* USER CODE END PTD */

typedef struct{
  uint16_t  Adavance_featuresSvcHdle;				/**< Adavance_features Service Handle */
  uint16_t  VersionCharHdle;			/**< VERSION Characteristic Handle */
/* USER CODE BEGIN Context */
  /* Place holder for Characteristic Descriptors Handle*/

/* USER CODE END Context */
}ADAVANCE_FEATURES_Context_t;

/* Private defines -----------------------------------------------------------*/

/* USER CODE BEGIN PD */

/* USER CODE END PD */

/* External variables --------------------------------------------------------*/

/* USER CODE BEGIN EV */

/* USER CODE END EV */

/* Private macros ------------------------------------------------------------*/
#define CHARACTERISTIC_DESCRIPTOR_ATTRIBUTE_OFFSET        2
#define CHARACTERISTIC_VALUE_ATTRIBUTE_OFFSET             1
#define VERSION_SIZE        11	/* VERSION Characteristic size */
/* USER CODE BEGIN PM */

/* USER CODE END PM */

/* Private variables ---------------------------------------------------------*/

static ADAVANCE_FEATURES_Context_t ADAVANCE_FEATURES_Context;

/* USER CODE BEGIN PV */

/* USER CODE END PV */

/* Private function prototypes -----------------------------------------------*/

/* USER CODE BEGIN PFP */

/* USER CODE END PFP */

/* Functions Definition ------------------------------------------------------*/
/* USER CODE BEGIN PFD */

/* USER CODE END PFD */

/* Private functions ----------------------------------------------------------*/

/*
 * UUIDs for Adavance features service
 */
#define ADAVANCE_FEATURES_UUID			0x8f,0xe5,0xb3,0xd5,0x2e,0x7f,0x4a,0x98,0x2a,0x48,0x7a,0xcc,0x50,0xfe,0x00,0x00
#define VERSION_UUID			0x8f,0xe5,0xb3,0xd5,0x2e,0x7f,0x4a,0x98,0x2a,0x48,0x7a,0xcc,0x51,0xfe,0x00,0x00

/* USER CODE BEGIN DESCRIPTORS DECLARATION */

/* USER CODE END DESCRIPTORS DECLARATION */

uint8_t version_val_buffer[VERSION_SIZE];

static ble_gatt_val_buffer_def_t version_val_buffer_def = {
  .op_flags = BLE_GATT_SRV_OP_MODIFIED_EVT_ENABLE_FLAG,
  .val_len = VERSION_SIZE,
  .buffer_len = sizeof(version_val_buffer),
  .buffer_p = version_val_buffer
};

/* Adavance features service characteristics definition */
static const ble_gatt_chr_def_t adavance_features_chars[] = {
	{
        .properties = BLE_GATT_SRV_CHAR_PROP_BROADCAST | BLE_GATT_SRV_CHAR_PROP_READ,
        .permissions = BLE_GATT_SRV_PERM_NONE,
        .min_key_size = 0x10,
        .uuid = BLE_UUID_INIT_128(VERSION_UUID),
        .val_buffer_p = &version_val_buffer_def
    },
};

/* Adavance features service definition */
static const ble_gatt_srv_def_t adavance_features_service = {
   .type = BLE_GATT_SRV_PRIMARY_SRV_TYPE,
   .uuid = BLE_UUID_INIT_128(ADAVANCE_FEATURES_UUID),
   .chrs = {
       .chrs_p = (ble_gatt_chr_def_t *)adavance_features_chars,
       .chr_count = 1U,
   },
};

/* USER CODE BEGIN PF */

/* USER CODE END PF */

/**
 * @brief  Event handler
 * @param  p_Event: Address of the buffer holding the p_Event
 * @retval Ack: Return whether the p_Event has been managed or not
 */
static BLEEVT_EvtAckStatus_t ADAVANCE_FEATURES_EventHandler(aci_blecore_event *p_evt)
{
  BLEEVT_EvtAckStatus_t return_value = BLEEVT_NoAck;
  aci_gatt_srv_read_event_rp0    *p_read;
  /* USER CODE BEGIN Service2_EventHandler_1 */

  /* USER CODE END Service2_EventHandler_1 */

  switch(p_evt->ecode)
  {
    case ACI_GATT_SRV_ATTRIBUTE_MODIFIED_VSEVT_CODE:
    {
      /* USER CODE BEGIN EVT_BLUE_GATT_ATTRIBUTE_MODIFIED_BEGIN */

      /* USER CODE END EVT_BLUE_GATT_ATTRIBUTE_MODIFIED_BEGIN */

      /* USER CODE BEGIN EVT_BLUE_GATT_ATTRIBUTE_MODIFIED_END */

      /* USER CODE END EVT_BLUE_GATT_ATTRIBUTE_MODIFIED_END */
      break;/* ACI_GATT_SRV_ATTRIBUTE_MODIFIED_VSEVT_CODE */
    }
    case ACI_GATT_SRV_READ_VSEVT_CODE :
    {
      /* USER CODE BEGIN EVT_BLUE_GATT_SRV_READ_BEGIN */

      /* USER CODE END EVT_BLUE_GATT_SRV_READ_BEGIN */
      p_read = (aci_gatt_srv_read_event_rp0*)p_evt->data;
	  if(p_read->Attribute_Handle == (ADAVANCE_FEATURES_Context.VersionCharHdle + CHARACTERISTIC_VALUE_ATTRIBUTE_OFFSET))
	  {
		return_value = BLEEVT_Ack;
		/*USER CODE BEGIN Service2_Char_1_ACI_GATT_SRV_READ_VSEVT_CODE_1 */
#warning user shall call aci_gatt_srv_read_resp() function if allowed
		/*USER CODE END Service2_Char_1_ACI_GATT_SRV_READ_VSEVT_CODE_1 */

		/*USER CODE BEGIN Service2_Char_1_ACI_GATT_SRV_READ_VSEVT_CODE_2 */

		  /*USER CODE END Service2_Char_1_ACI_GATT_SRV_READ_VSEVT_CODE_2 */
	  } /* if(p_read->Attribute_Handle == (ADAVANCE_FEATURES_Context.VersionCharHdle + CHARACTERISTIC_VALUE_ATTRIBUTE_OFFSET))*/

      /* USER CODE BEGIN EVT_BLUE_GATT_SRV_READ_END */

      /* USER CODE END EVT_EVT_BLUE_GATT_SRV_READ_END */
      break;/* ACI_GATT_SRV_READ_VSEVT_CODE */
    }
    case ACI_GATT_SRV_WRITE_VSEVT_CODE:
    {
      /* USER CODE BEGIN EVT_BLUE_SRV_GATT_BEGIN */

      /* USER CODE END EVT_BLUE_SRV_GATT_BEGIN */

      /* USER CODE BEGIN EVT_BLUE_GATT_SRV_WRITE_END */

      /* USER CODE END EVT_BLUE_GATT_SRV_WRITE_END */
      break;/* ACI_GATT_SRV_WRITE_VSEVT_CODE */
    }
    case ACI_GATT_TX_POOL_AVAILABLE_VSEVT_CODE:
    {
      aci_gatt_tx_pool_available_event_rp0 *p_tx_pool_available_event;
      p_tx_pool_available_event = (aci_gatt_tx_pool_available_event_rp0 *) p_evt->data;
      UNUSED(p_tx_pool_available_event);

      /* USER CODE BEGIN ACI_GATT_TX_POOL_AVAILABLE_VSEVT_CODE */

      /* USER CODE END ACI_GATT_TX_POOL_AVAILABLE_VSEVT_CODE */
      break;/* ACI_GATT_TX_POOL_AVAILABLE_VSEVT_CODE*/
    }
    case ACI_ATT_EXCHANGE_MTU_RESP_VSEVT_CODE:
    {
      aci_att_exchange_mtu_resp_event_rp0 *p_exchange_mtu;
      p_exchange_mtu = (aci_att_exchange_mtu_resp_event_rp0 *)  p_evt->data;
      UNUSED(p_exchange_mtu);

      /* USER CODE BEGIN ACI_ATT_EXCHANGE_MTU_RESP_VSEVT_CODE */

      /* USER CODE END ACI_ATT_EXCHANGE_MTU_RESP_VSEVT_CODE */
      break;/* ACI_ATT_EXCHANGE_MTU_RESP_VSEVT_CODE */
    }
    /* USER CODE BEGIN BLECORE_EVT */

    /* USER CODE END BLECORE_EVT */
  default:
    /* USER CODE BEGIN EVT_DEFAULT */

    /* USER CODE END EVT_DEFAULT */
    break;
  }

  /* USER CODE BEGIN Service2_EventHandler_2 */

  /* USER CODE END Service2_EventHandler_2 */

  return(return_value);
}/* end ADAVANCE_FEATURES_EventHandler */

/* Public functions ----------------------------------------------------------*/

/**
 * @brief  Service initialization
 * @param  None
 * @retval None
 */
void ADAVANCE_FEATURES_Init(void)
{
  tBleStatus ret = BLE_STATUS_INVALID_PARAMS;
  UNUSED(ADAVANCE_FEATURES_Context);

  /* USER CODE BEGIN InitService2Svc_1 */

  /* USER CODE END InitService2Svc_1 */

  /**
   *  Register the event handler to the BLE controller
   */
  BLEEVT_RegisterGattEvtHandler(ADAVANCE_FEATURES_EventHandler);

  ret = aci_gatt_srv_add_service((ble_gatt_srv_def_t *)&adavance_features_service);

  if (ret != BLE_STATUS_SUCCESS)
  {
    APP_DBG_MSG("  Fail   : aci_gatt_srv_add_service command: Adavance_features, error code: 0x%x \n", ret);
  }
  else
  {
    APP_DBG_MSG("  Success: aci_gatt_srv_add_service command: Adavance_features \n");
  }

  ADAVANCE_FEATURES_Context.Adavance_featuresSvcHdle = aci_gatt_srv_get_service_handle((ble_gatt_srv_def_t *) &adavance_features_service);
  ADAVANCE_FEATURES_Context.VersionCharHdle = aci_gatt_srv_get_char_decl_handle((ble_gatt_chr_def_t *)&adavance_features_chars[0]);

  /* USER CODE BEGIN InitService1Svc_2 */

  /* USER CODE END InitService1Svc_2 */

  if (ret != BLE_STATUS_SUCCESS)
  {
    APP_DBG_MSG("  Fail registering Adavance_features handlers\n");
  }

  return;
}

/**
 * @brief  Characteristic update
 * @param  CharOpcode: Characteristic identifier
 * @param  pData: pointer to the new data to be written in the characteristic
 *
 */
tBleStatus ADAVANCE_FEATURES_UpdateValue(ADAVANCE_FEATURES_CharOpcode_t CharOpcode, ADAVANCE_FEATURES_Data_t *pData)
{
  tBleStatus ret = BLE_STATUS_SUCCESS;

  /* USER CODE BEGIN Service2_App_Update_Char_1 */

  /* USER CODE END Service2_App_Update_Char_1 */

  switch(CharOpcode)
  {
    case ADAVANCE_FEATURES_VERSION:
      memcpy(version_val_buffer, pData->p_Payload, MIN(pData->Length, sizeof(version_val_buffer)));
      /* USER CODE BEGIN Service2_Char_Value_1*/

      /* USER CODE END Service2_Char_Value_1*/
      break;

    default:
      break;
  }

  /* USER CODE BEGIN Service2_App_Update_Char_2 */

  /* USER CODE END Service2_App_Update_Char_2 */

  return ret;
}

/**
 * @brief  Characteristic notification
 * @param  CharOpcode: Characteristic identifier
 * @param  pData: pointer to the data to be notified to the client
 * @param  ConnectionHandle: connection handle identifying the client to be notified.
 *
 */
tBleStatus ADAVANCE_FEATURES_NotifyValue(ADAVANCE_FEATURES_CharOpcode_t CharOpcode, ADAVANCE_FEATURES_Data_t *pData, uint16_t ConnectionHandle)
{
  tBleStatus ret = BLE_STATUS_INVALID_PARAMS;
  /* USER CODE BEGIN Service2_App_Notify_Char_1 */

  /* USER CODE END Service2_App_Notify_Char_1 */

  switch(CharOpcode)
  {

    default:
      break;
  }

  /* USER CODE BEGIN Service2_App_Notify_Char_2 */

  /* USER CODE END Service2_App_Notify_Char_2 */

  return ret;
}
