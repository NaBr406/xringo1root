package moe.shizuku.manager.adb

/** Stand-in for androidx.lifecycle.Observer. */
fun interface Observer<T> {
    fun onChanged(value: T)
}
