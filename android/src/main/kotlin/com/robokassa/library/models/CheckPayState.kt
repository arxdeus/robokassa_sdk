package com.robokassa.library.models

import android.util.Xml
import com.robokassa.library.errors.RoboApiException
import com.robokassa.library.helper.Logger
import org.xmlpull.v1.XmlPullParser
import java.io.StringReader

/**
 * Объект с результатом обработки платежного окна Robokassa.
 * @property requestCode
 * @property stateCode
 * @property desc
 * @property opKey
 * @property error
 */
data class CheckPayState(
    val requestCode: CheckRequestCode,
    val stateCode: CheckPayStateCode,
    val desc: String? = null,
    val opKey: String? = null,
    val error: RoboApiException? = null
) : RoboApiResponse() {

    companion object {
        fun parse(src: String?): CheckPayState {
            var codeParse = ""
            var stateCodeParse = ""
            var descParse = ""
            var opKey = ""
            try {
                if (src != null) {
                    val root = parseElement(src)
                    if (root.name != "OperationStateResponse") {
                        throw IllegalArgumentException("Unexpected root element ${root.name}")
                    }
                    root.child("Result")?.let {
                        codeParse = it.text("Code")
                        descParse = it.text("Description")
                    }
                    root.child("State")?.let { stateCodeParse = it.text("Code") }
                    root.child("Info")?.let { opKey = it.text("OpKey") }
                }
            } catch (e: Exception) {
                Logger.e("Check parse error $e")
                return CheckPayState(
                    stateCode = CheckPayStateCode.NOT_INITED,
                    requestCode = CheckRequestCode.CHECKING
                )
            }
            var requestCode = CheckRequestCode.CHECKING

            when (codeParse) {
                CheckRequestCode.SUCCESS.code -> requestCode = CheckRequestCode.SUCCESS
                CheckRequestCode.SIGNATURE_ERROR.code -> requestCode = CheckRequestCode.SIGNATURE_ERROR
                CheckRequestCode.SHOP_ERROR.code -> requestCode = CheckRequestCode.SHOP_ERROR
                CheckRequestCode.INVOICE_ZERO_ERROR.code -> requestCode = CheckRequestCode.INVOICE_ZERO_ERROR
                CheckRequestCode.INVOICE_DOUBLE_ERROR.code -> requestCode = CheckRequestCode.INVOICE_DOUBLE_ERROR
                CheckRequestCode.SERVER_ERROR.code -> requestCode = CheckRequestCode.SERVER_ERROR
            }

            var stateCode = CheckPayStateCode.NOT_INITED
            when (stateCodeParse) {
                CheckPayStateCode.INITED_NOT_PAYED.code -> stateCode = CheckPayStateCode.INITED_NOT_PAYED
                CheckPayStateCode.CANCELLED_NOT_PAYED.code -> stateCode = CheckPayStateCode.CANCELLED_NOT_PAYED
                CheckPayStateCode.HOLD_SUCCESS.code -> stateCode = CheckPayStateCode.HOLD_SUCCESS
                CheckPayStateCode.PAYED_NOT_TRANSFERRED.code -> stateCode = CheckPayStateCode.PAYED_NOT_TRANSFERRED
                CheckPayStateCode.PAYMENT_PAYBACK.code -> stateCode = CheckPayStateCode.PAYMENT_PAYBACK
                CheckPayStateCode.PAYMENT_STOPPED.code -> stateCode = CheckPayStateCode.PAYMENT_STOPPED
                CheckPayStateCode.PAYMENT_SUCCESS.code -> stateCode = CheckPayStateCode.PAYMENT_SUCCESS
            }
            return CheckPayState(
                stateCode = stateCode,
                requestCode = requestCode,
                desc = descParse,
                opKey = opKey
            )
        }
    }

}

// ponytail: hand-rolled pull parse of one fixed, known, non-namespaced shape
// (OperationStateResponse > Result|State|Info > Code|Description|OpKey). Replaces
// upstream's konsume-xml, which is JitPack-only. Swap in a real XML binding
// library only if this response schema grows beyond a couple of nested levels.
private class XmlElement(val name: String) {
    val children = mutableListOf<XmlElement>()
    var text: String = ""

    fun child(name: String): XmlElement? = children.firstOrNull { it.name == name }

    /** Text of the first *direct* child named [name], or "" when absent. */
    fun text(name: String): String = child(name)?.text ?: ""
}

/** Parses [src] into the document element, throwing on malformed XML. */
private fun parseElement(src: String): XmlElement {
    val parser = Xml.newPullParser()
    parser.setFeature(XmlPullParser.FEATURE_PROCESS_NAMESPACES, false)
    parser.setInput(StringReader(src))
    while (parser.next() != XmlPullParser.START_TAG) {
        if (parser.eventType == XmlPullParser.END_DOCUMENT) {
            throw IllegalArgumentException("No root element")
        }
    }
    return readElement(parser)
}

/** Reads the element the parser is positioned on, leaving it on its END_TAG. */
private fun readElement(parser: XmlPullParser): XmlElement {
    val element = XmlElement(parser.name)
    val text = StringBuilder()
    while (parser.next() != XmlPullParser.END_TAG) {
        when (parser.eventType) {
            XmlPullParser.START_TAG -> element.children.add(readElement(parser))
            XmlPullParser.TEXT -> text.append(parser.text)
            XmlPullParser.END_DOCUMENT ->
                throw IllegalArgumentException("Unclosed element ${element.name}")
        }
    }
    element.text = text.toString().trim()
    return element
}
