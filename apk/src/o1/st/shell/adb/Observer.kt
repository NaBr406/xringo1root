package o1.st.shell.adb

/** Stand-in for androidx.lifecycle.Observer. */
fun interface Observer<T> {
    fun onChanged(value: T)
}
